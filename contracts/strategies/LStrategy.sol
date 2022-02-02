// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/IVaultRegistry.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../interfaces/oracles/IOracle.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControl.sol";

contract LStrategy is ContractMeta, Multicall, DefaultAccessControl {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint256 public constant DENOMINATOR = 10**9;
    bytes4 public constant SET_PRESIGNATURE_SELECTOR = 0xec6cb13f;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    address[] public tokens;
    IERC20Vault public immutable erc20Vault;
    INonfungiblePositionManager public immutable positionManager;
    uint24 public immutable poolFee;
    address public immutable cowswap;

    // INTERNAL STATE

    IUniV3Vault public lowerVault;
    IUniV3Vault public upperVault;
    uint256 public lastUniV3RebalanceTimestamp;
    uint256 public tickPointTimestamp;

    // MUTABLE PARAMS

    struct TradingParams {
        uint256 maxSlippageD;
        uint256 minRebalanceWaitTime;
        uint32 orderDeadline;
        uint8 oracleSafety;
        IOracle oracle;
    }

    struct RatioParams {
        uint256 erc20UniV3CapitalRatioD;
        uint256 erc20TokenRatioD;
    }
    struct BotParams {
        uint256 maxBotAllowance;
        uint256 minBotWaitTime;
    }

    struct OtherParams {
        uint16 intervalWidthInTicks;
        uint256 lowerTickDeviation;
        uint256 upperTickDeviation;
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
    }

    struct PreOrder {
        address tokenIn;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
    }

    struct CowswapOrder {
        address tokenIn;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
    }

    TradingParams public tradingParams;
    RatioParams public ratioParams;
    BotParams public botParams;
    OtherParams public otherParams;
    PreOrder public preOrder;

    // @notice Constructor for a new contract
    // @param positionManager_ Reference to UniswapV3 positionManager
    // @param erc20vault_ Reference to ERC20 Vault
    // @param vault1_ Reference to Uniswap V3 Vault 1
    // @param vault2_ Reference to Uniswap V3 Vault 2
    constructor(
        INonfungiblePositionManager positionManager_,
        address cowswap_,
        IERC20Vault erc20vault_,
        IUniV3Vault vault1_,
        IUniV3Vault vault2_,
        address admin_
    ) DefaultAccessControl(admin_) {
        positionManager = positionManager_;
        erc20Vault = erc20vault_;
        lowerVault = vault1_;
        upperVault = vault2_;
        tokens = vault1_.vaultTokens();
        poolFee = vault1_.pool().fee();
        cowswap = cowswap_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Target price based on mutable params
    function targetPrice(address[] memory tokens_, TradingParams memory tradingParams_)
        public
        view
        returns (uint256 priceX96)
    {
        (uint256[] memory prices, ) = tradingParams_.oracle.price(
            tokens_[0],
            tokens_[1],
            1 << tradingParams_.oracleSafety
        );
        require(prices.length > 0, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < prices.length; i++) {
            priceX96 += prices[i];
        }
        priceX96 /= prices.length;
    }

    /// @notice Target liquidity ratio for UniV3 vaults
    function targetUniV3LiquidityRatio(int24 targetTick_)
        public
        view
        returns (uint256 liquidityRatioD, bool isNegative)
    {
        (int24 tickLower, int24 tickUpper, ) = _getVaultStats(lowerVault);
        int24 midTick = (tickUpper + tickLower) / 2;
        isNegative = midTick > targetTick_;
        if (isNegative) {
            liquidityRatioD = FullMath.mulDiv(
                uint256(uint24(midTick - targetTick_)),
                DENOMINATOR,
                uint256(uint24((tickUpper - tickLower) / 2))
            );
        } else {
            liquidityRatioD = FullMath.mulDiv(
                uint256(uint24(targetTick_ - midTick)),
                DENOMINATOR,
                uint256(uint24((tickUpper - tickLower) / 2))
            );
        }
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    function postPreOrder() external {
        _requireAtLeastOperator();
        (uint256[] memory tvl, ) = erc20Vault.tvl();
        (uint256 tokenDelta, bool isNegative) = _liquidityDelta(tvl[0], tvl[0] + tvl[1], ratioParams.erc20TokenRatioD);
        TradingParams memory tradingParams_ = tradingParams;
        uint256 priceX96 = targetPrice(tokens, tradingParams_);
        if (isNegative) {
            uint256 minAmountOut = FullMath.mulDiv(tokenDelta, CommonLibrary.Q96, priceX96);
            minAmountOut = FullMath.mulDiv(minAmountOut, DENOMINATOR - tradingParams_.maxSlippageD, DENOMINATOR);
            preOrder = PreOrder({
                tokenIn: tokens[1],
                amountIn: tokenDelta,
                minAmountOut: minAmountOut,
                deadline: block.timestamp + tradingParams_.orderDeadline
            });
        } else {
            uint256 minAmountOut = FullMath.mulDiv(tokenDelta, priceX96, CommonLibrary.Q96);
            minAmountOut = FullMath.mulDiv(minAmountOut, DENOMINATOR - tradingParams_.maxSlippageD, DENOMINATOR);
            preOrder = PreOrder({
                tokenIn: tokens[1],
                amountIn: tokenDelta,
                minAmountOut: minAmountOut,
                deadline: block.timestamp + tradingParams_.orderDeadline
            });
        }
    }

    /// Sign Cowswap order
    /// @param tokenNumber The number of the token to swap
    /// @param allowance Allowance to set for cowswap
    /// @param uuid Cowswap order id
    /// @param signed To sign order set to `true`
    function signOrder(
        CowswapOrder memory order,
        bytes calldata uuid,
        bool signed
    ) external {
        _requireAtLeastOperator();
        // https://github.com/gnosis/gp-v2-contracts/blob/main/src/contracts/libraries/GPv2Order.sol#L134
        // https://github.com/gnosis/gp-v2-contracts/blob/main/src/contracts/libraries/GPv2Order.sol#L228
        // https://github.com/gnosis/gp-v2-contracts/blob/main/src/contracts/mixins/GPv2Signing.sol#L154
        // https://etherscan.io/address/0x9008d19f58aabd9ed0d60971565aa8510560ab41#readContract - DOMAIN SEPARATOR

        PreOrder memory preOrder_ = preOrder;
        require(preOrder_.deadline >= block.timestamp, ExceptionsLibrary.TIMESTAMP);
        if (!signed) {
            bytes memory resetData = abi.encodeWithSelector(SET_PRESIGNATURE_SELECTOR, uuid, false);
            erc20Vault.externalCall(cowswap, resetData);
            return;
        }

        bytes32 orderHash;
        assembly {
            mstore(orderHash, uuid.offset)
        }
        // take it from gnosis lib
        require(order.hash == orderHash, ExceptionsLibrary.INVARIANT);
        require(order.tokenIn == preOrder_.tokenIn, ExceptionsLibrary.INVALID_TOKEN);
        require(order.amountIn == preOrder_.amountIn, ExceptionsLibrary.INVALID_VALUE);
        require(order.minAmountOut >= preOrder_.minAmountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);
        bytes memory approveData = abi.encode(cowswap, order.amountIn);
        erc20Vault.externalCall(order.tokenIn, APPROVE_SELECTOR, approveData);
        bytes memory setPresignatureData = abi.encode(SET_PRESIGNATURE_SELECTOR, uuid, signed);
        erc20Vault.externalCall(cowswap, SET_PRESIGNATURE_SELECTOR, setPresignatureData);
    }

    function resetCowswapAllowance(uint8 tokenNumber) external {
        _requireAtLeastOperator();
        bytes memory approveData = abi.encodeWithSelector(APPROVE_SELECTOR, abi.encode(cowswap, 0));
        erc20Vault.externalCall(tokens[tokenNumber], approveData);
    }

    /// @notice Collect Uniswap pool fees to erc20 vault
    function collectUniFees() external {
        _requireAtLeastOperator();
        lowerVault.collectEarnings();
        upperVault.collectEarnings();
    }

    /// @notice Manually pull tokens from fromVault to toVault
    /// @param fromVault Pull tokens from this vault
    /// @param toVault Pull tokens to this vault
    /// @param tokenAmounts Token amounts to pull
    /// @param minTokensAmounts Minimal token amounts to pull
    /// @param deadline Timestamp after which the transaction is invalid
    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts,
        uint256[] memory minTokensAmounts,
        uint256 deadline
    ) external {
        _requireAdmin();
        fromVault.pull(address(toVault), tokens, tokenAmounts, _makeUniswapVaultOptions(minTokensAmounts, deadline));
    }

    function rebalanceERC20UniV3Vaults(
        uint256[] memory minLowerVaultTokens,
        uint256[] memory minUpperVaultTokens,
        uint256 deadline
    ) external {
        _requireAtLeastOperator();
        uint256 capitalDelta;
        bool isNegativeCapitalDelta;
        uint256 priceX96 = targetPrice(tokens, tradingParams);
        uint256 erc20VaultCapital = _getCapital(priceX96, erc20Vault);
        uint256 lowerVaultCapital = _getCapital(priceX96, lowerVault);
        uint256 upperVaultCapital = _getCapital(priceX96, upperVault);
        (capitalDelta, isNegativeCapitalDelta) = _liquidityDelta(
            erc20VaultCapital,
            erc20VaultCapital + lowerVaultCapital + upperVaultCapital,
            ratioParams.erc20UniV3CapitalRatioD
        );
        uint256 percentageIncreaseD = FullMath.mulDiv(DENOMINATOR, capitalDelta, lowerVaultCapital + upperVaultCapital);
        (, , uint128 lowerVaultLiquidity) = _getVaultStats(lowerVault);
        (, , uint128 upperVaultLiquidity) = _getVaultStats(upperVault);
        uint256 lowerVaultDelta = FullMath.mulDiv(percentageIncreaseD, lowerVaultLiquidity, DENOMINATOR);
        uint256 upperVaultDelta = FullMath.mulDiv(percentageIncreaseD, upperVaultLiquidity, DENOMINATOR);
        uint256[] memory lowerTokenAmounts = lowerVault.liquidityToTokenAmounts(uint128(lowerVaultDelta));
        uint256[] memory upperTokenAmounts = upperVault.liquidityToTokenAmounts(uint128(upperVaultDelta));

        if (!isNegativeCapitalDelta) {
            erc20Vault.pull(
                address(lowerVault),
                tokens,
                lowerTokenAmounts,
                _makeUniswapVaultOptions(minLowerVaultTokens, deadline)
            );
            erc20Vault.pull(
                address(lowerVault),
                tokens,
                upperTokenAmounts,
                _makeUniswapVaultOptions(minUpperVaultTokens, deadline)
            );
        } else {
            lowerVault.pull(
                address(erc20Vault),
                tokens,
                lowerTokenAmounts,
                _makeUniswapVaultOptions(minLowerVaultTokens, deadline)
            );
            upperVault.pull(
                address(erc20Vault),
                tokens,
                upperTokenAmounts,
                _makeUniswapVaultOptions(minUpperVaultTokens, deadline)
            );
        }
    }

    /// @notice Make a rebalance of UniV3 vaults
    /// @param minWithdrawTokens Min accepted tokenAmounts for withdrawal
    /// @param minDepositTokens Min accepted tokenAmounts for deposit
    /// @param deadline Timestamp after which the transaction reverts
    function rebalanceUniV3Vaults(
        uint256[] memory minWithdrawTokens,
        uint256[] memory minDepositTokens,
        uint256 deadline
    ) external {
        _requireAtLeastOperator();
        uint256 targetPriceX96 = targetPrice(tokens, tradingParams);
        int24 targetTick = _tickFromPriceX96(targetPriceX96);
        (uint256 targetUniV3LiquidityRatioD, bool isNegativeLiquidityRatio) = targetUniV3LiquidityRatio(targetTick);
        // // we crossed the interval right to left
        if (isNegativeLiquidityRatio) {
            (, , uint128 liquidity) = _getVaultStats(upperVault);
            if (liquidity > 0) {
                // pull all liquidity to other vault and swap intervals
                _rebalanceUniV3Liquidity(
                    upperVault,
                    lowerVault,
                    type(uint128).max,
                    minWithdrawTokens,
                    minDepositTokens,
                    deadline
                );
            } else {
                _swapVaults(false, deadline);
            }
            return;
        }
        // we crossed the interval left to right
        if (targetUniV3LiquidityRatioD > DENOMINATOR) {
            (, , uint128 liquidity) = _getVaultStats(lowerVault);
            if (liquidity > 0) {
                _rebalanceUniV3Liquidity(
                    lowerVault,
                    upperVault,
                    type(uint128).max,
                    minWithdrawTokens,
                    minDepositTokens,
                    deadline
                );
            } else {
                _swapVaults(true, deadline);
            }
            return;
        }

        (, , uint128 lowerLiquidity) = _getVaultStats(lowerVault);
        (, , uint128 upperLiquidity) = _getVaultStats(upperVault);
        (uint256 liquidityDelta, bool isNegativeLiquidityDelta) = _liquidityDelta(
            lowerLiquidity,
            upperLiquidity,
            targetUniV3LiquidityRatioD
        );
        IUniV3Vault fromVault;
        IUniV3Vault toVault;
        if (isNegativeLiquidityDelta) {
            fromVault = upperVault;
            toVault = lowerVault;
        } else {
            fromVault = lowerVault;
            toVault = upperVault;
        }
        _rebalanceUniV3Liquidity(
            fromVault,
            toVault,
            uint128(liquidityDelta),
            minWithdrawTokens,
            minDepositTokens,
            deadline
        );
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("LStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Calculate a pure (not Uniswap) liquidity
    /// @param priceX96 Current price y / x
    /// @param vault Vault for liquidity calculation
    /// @return Capital = x * p + y
    function _getCapital(uint256 priceX96, IVault vault) internal view returns (uint256) {
        (uint256[] memory tvl, ) = vault.tvl();
        return FullMath.mulDiv(tvl[0], priceX96, CommonLibrary.Q96) + tvl[1];
    }

    /// @notice Target tick based on mutable params
    function _tickFromPriceX96(uint256 priceX96) internal pure returns (int24) {
        uint256 sqrtPriceX96 = CommonLibrary.sqrtX96(priceX96);
        return TickMath.getTickAtSqrtRatio(uint160(sqrtPriceX96));
    }

    function _priceX96FromTick(int24 _tick) internal pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
    }

    /// @notice The vault to get stats from
    /// @return tickLower Lower tick for the uniV3 poistion inside the vault
    /// @return tickUpper Upper tick for the uniV3 poistion inside the vault
    /// @return liquidity Vault liquidity
    function _getVaultStats(IUniV3Vault vault)
        internal
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        uint256 nft = vault.uniV3Nft();
        (, , , , , tickLower, tickUpper, liquidity, , , , ) = positionManager.positions(nft);
    }

    /// @notice Liquidity required to be sold to reach targetLiquidityRatioD
    /// @param lowerLiquidity Lower vault liquidity
    /// @param upperLiquidity Upper vault liquidity
    /// @param targetLiquidityRatioD Tardet liquidity ratio (multiplied by DENOMINATOR)
    /// @return delta Liquidity required to reach targetLiquidityRatioD
    /// @return isNegative If `true` then delta needs to be bought to reach targetLiquidityRatioD, o/w needs to be sold
    function _liquidityDelta(
        uint256 lowerLiquidity,
        uint256 upperLiquidity,
        uint256 targetLiquidityRatioD
    ) internal pure returns (uint256 delta, bool isNegative) {
        uint256 targetLowerLiquidity = FullMath.mulDiv(
            targetLiquidityRatioD,
            uint256(lowerLiquidity + upperLiquidity),
            DENOMINATOR
        );
        if (targetLowerLiquidity > lowerLiquidity) {
            isNegative = true;
            delta = targetLowerLiquidity - lowerLiquidity;
        } else {
            isNegative = false;
            delta = lowerLiquidity - targetLowerLiquidity;
        }
    }

    /// @notice Covert token amounts and deadline to byte options
    /// @dev Empty tokenAmounts are equivalent to zero tokenAmounts
    function _makeUniswapVaultOptions(uint256[] memory tokenAmounts, uint256 deadline)
        internal
        pure
        returns (bytes memory options)
    {
        options = new bytes(0x60);
        assembly {
            mstore(add(options, 0x60), deadline)
        }
        if (tokenAmounts.length == 2) {
            uint256 tokenAmount0 = tokenAmounts[0];
            uint256 tokenAmount1 = tokenAmounts[1];
            assembly {
                mstore(add(options, 0x20), tokenAmount0)
                mstore(add(options, 0x40), tokenAmount1)
            }
        }
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    /// @notice Pull liquidity from `fromVault` and put into `toVault`
    /// @param fromVault The vault to pull liquidity from
    /// @param toVault The vault to pull liquidity to
    /// @param desiredLiquidity The amount of liquidity desired for rebalance. This could be cut to available erc20 vault balance and available uniV3 vault liquidity.
    /// @param minWithdrawTokens Min accepted tokenAmounts for withdrawal
    /// @param minDepositTokens Min accepted tokenAmounts for deposit
    /// @param deadline Timestamp after which the transaction reverts
    /// @return pulledAmounts amounts pulled from fromVault
    /// @return pushedAmounts amounts pushed to toVault
    function _rebalanceUniV3Liquidity(
        IUniV3Vault fromVault,
        IUniV3Vault toVault,
        uint128 desiredLiquidity,
        uint256[] memory minWithdrawTokens,
        uint256[] memory minDepositTokens,
        uint256 deadline
    ) internal returns (uint256[] memory pulledAmounts, uint256[] memory pushedAmounts) {
        address[] memory tokens_ = tokens;
        uint128 liquidity = desiredLiquidity;

        // Cut for available liquidity in the vault
        (, , uint128 fromVaultLiquidity) = _getVaultStats(fromVault);
        liquidity = fromVaultLiquidity > liquidity ? liquidity : fromVaultLiquidity;

        //--- Cut rebalance to available token balances on ERC20 Vault
        // The rough idea is to translate one unit of liquituty into tokens for each interval shouldDepositTokenAmountsD, shouldWithdrawTokenAmountsD
        // Then the actual tokens in the vault are shouldDepositTokenAmountsD * l, shouldWithdrawTokenAmountsD * l
        // So the equation could be built: erc20 balances + l * shouldWithdrawTokenAmountsD >= l * shouldDepositTokenAmountsD and l tweaked so this inequality holds
        (uint256[] memory availableBalances, ) = erc20Vault.tvl();
        uint256[] memory shouldDepositTokenAmountsD = toVault.liquidityToTokenAmounts(uint128(DENOMINATOR));
        uint256[] memory shouldWithdrawTokenAmountsD = fromVault.liquidityToTokenAmounts(uint128(DENOMINATOR));
        for (uint256 i = 0; i < 2; i++) {
            uint256 availableBalance = availableBalances[i] +
                FullMath.mulDiv(shouldWithdrawTokenAmountsD[i], liquidity, DENOMINATOR);
            uint256 requiredBalance = FullMath.mulDiv(shouldDepositTokenAmountsD[i], liquidity, DENOMINATOR);
            if (availableBalance < requiredBalance) {
                // since balances >= 0, this case means that shouldWithdrawTokenAmountsD < shouldDepositTokenAmountsD
                // this also means that liquidity on the line below will decrease compared to the liqiduity above
                liquidity = uint128(
                    FullMath.mulDiv(
                        availableBalances[i],
                        shouldDepositTokenAmountsD[i] - shouldWithdrawTokenAmountsD[i],
                        DENOMINATOR
                    )
                );
            }
        }
        //--- End cut

        uint256[] memory depositTokenAmounts = toVault.liquidityToTokenAmounts(liquidity);
        uint256[] memory withdrawTokenAmounts = fromVault.liquidityToTokenAmounts(liquidity);
        pulledAmounts = fromVault.pull(
            address(erc20Vault),
            tokens_,
            withdrawTokenAmounts,
            _makeUniswapVaultOptions(minWithdrawTokens, deadline)
        );
        // The pull is on best effort so we don't worry on overflow
        pushedAmounts = erc20Vault.pull(
            address(toVault),
            tokens_,
            depositTokenAmounts,
            _makeUniswapVaultOptions(minDepositTokens, deadline)
        );
        emit RebalancedUniV3(
            address(fromVault),
            address(toVault),
            pulledAmounts,
            pushedAmounts,
            desiredLiquidity,
            liquidity
        );
    }

    /// @notice Closes position with zero liquidity and creates a new one.
    /// @dev This happens when the price croses "zero" point and a new interval must be created while old one is close
    /// @param positiveTickGrowth `true` if price tick increased
    /// @param deadline Deadline for Uniswap V3 operations
    function _swapVaults(bool positiveTickGrowth, uint256 deadline) internal {
        IUniV3Vault fromVault;
        IUniV3Vault toVault;
        if (!positiveTickGrowth) {
            (fromVault, toVault) = (lowerVault, upperVault);
        } else {
            (fromVault, toVault) = (upperVault, lowerVault);
        }
        uint256 fromNft = fromVault.uniV3Nft();
        uint256 toNft = toVault.uniV3Nft();

        {
            fromVault.collectEarnings();
            (, , , , , , , uint128 fromLiquidity, , , , ) = positionManager.positions(fromNft);
            require(fromLiquidity == 0, ExceptionsLibrary.INVARIANT);
        }

        (, , , , , int24 toTickLower, int24 toTickUpper, , , , , ) = positionManager.positions(toNft);
        int24 newTickLower;
        int24 newTickUpper;
        if (positiveTickGrowth) {
            newTickLower = (toTickLower + toTickUpper) / 2;
            newTickUpper = newTickLower + int24(uint24(otherParams.intervalWidthInTicks));
        } else {
            newTickUpper = (toTickLower + toTickUpper) / 2;
            newTickLower = newTickUpper - int24(uint24(otherParams.intervalWidthInTicks));
        }

        uint256 newNft = _mintNewNft(newTickLower, newTickUpper, deadline);
        positionManager.safeTransferFrom(address(this), address(fromVault), newNft);
        positionManager.burn(fromNft);

        (lowerVault, upperVault) = (upperVault, lowerVault);

        emit SwapVault(fromNft, newNft, newTickLower, newTickUpper);
    }

    /// @notice Mints new Nft in Uniswap V3 positionManager
    /// @param lowerTick Lower tick of the Uni interval
    /// @param upperTick Upper tick of the Uni interval
    /// @param deadline Timestamp after which the transaction will be reverted
    function _mintNewNft(
        int24 lowerTick,
        int24 upperTick,
        uint256 deadline
    ) internal returns (uint256 newNft) {
        uint256 minToken0ForOpening = otherParams.minToken0ForOpening;
        uint256 minToken1ForOpening = otherParams.minToken1ForOpening;
        IERC20(tokens[0]).safeApprove(address(positionManager), minToken0ForOpening);
        IERC20(tokens[1]).safeApprove(address(positionManager), minToken1ForOpening);
        (newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: poolFee,
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: minToken0ForOpening,
                amount1Desired: minToken1ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );
        IERC20(tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(tokens[1]).safeApprove(address(positionManager), 0);
    }

    /// @notice Emitted when vault is swapped.
    /// @param oldNft UniV3 nft that was burned
    /// @param newNft UniV3 nft that was created
    /// @param newTickLower Lower tick for created UniV3 nft
    /// @param newTickUpper Upper tick for created UniV3 nft
    event SwapVault(uint256 oldNft, uint256 newNft, int24 newTickLower, int24 newTickUpper);

    /// @param fromVault The vault to pull liquidity from
    /// @param toVault The vault to pull liquidity to
    /// @param pulledAmounts amounts pulled from fromVault
    /// @param pushedAmounts amounts pushed to toVault
    /// @param desiredLiquidity The amount of liquidity desired for rebalance. This could be cut to available erc20 vault balance and available uniV3 vault liquidity.
    /// @param liquidity The actual amount of liquidity rebalanced.
    event RebalancedUniV3(
        address fromVault,
        address toVault,
        uint256[] pulledAmounts,
        uint256[] pushedAmounts,
        uint128 desiredLiquidity,
        uint128 liquidity
    );
}
