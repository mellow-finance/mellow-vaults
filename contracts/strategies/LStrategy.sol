// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/IVaultRegistry.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../utils/ContractMeta.sol";

contract LStrategy is ContractMeta, Multicall {
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
    uint256 public tickPointTimestamp;

    // MUTABLE PARAMS

    struct TickParams {
        int24 tickPoint;
        int24 annualTickGrowth;
    }

    struct RatioParams {
        uint256 erc20UniV3RatioD;
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

    TickParams public tickParams;
    RatioParams public ratioParams;
    BotParams public botParams;
    OtherParams public otherParams;

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
        IUniV3Vault vault2_
    ) {
        positionManager = positionManager_;
        erc20Vault = erc20vault_;
        lowerVault = vault1_;
        upperVault = vault2_;
        tokens = vault1_.vaultTokens();
        poolFee = vault1_.pool().fee();
        cowswap = cowswap_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Target tick based on mutable params
    function targetTick() public view returns (int24) {
        uint256 timeDelta = block.timestamp - tickPointTimestamp;
        int24 annualTickGrowth = tickParams.annualTickGrowth;
        int24 tickPoint = tickParams.tickPoint;
        if (annualTickGrowth > 0) {
            return
                tickPoint +
                int24(uint24(FullMath.mulDiv(uint256(uint24(annualTickGrowth)), timeDelta, CommonLibrary.YEAR)));
        } else {
            return
                tickPoint -
                int24(uint24(FullMath.mulDiv(uint256(uint24(-annualTickGrowth)), timeDelta, CommonLibrary.YEAR)));
        }
    }

    /// @notice Target liquidity ratio for UniV3 vaults
    function targetUniV3LiquidityRatio() public view returns (uint256 liquidityRatioD, bool isNegative) {
        int24 targetTick_ = targetTick();
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

    /// Sign Cowswap order
    /// @param tokenNumber The number of the token to swap
    /// @param allowance Allowance to set for cowswap
    /// @param uuid Cowswap order id
    /// @param signed To sign order set to `true`
    function signOrder(
        uint8 tokenNumber,
        uint256 allowance,
        bytes calldata uuid,
        bool signed
    ) external {
        erc20Vault.externalCall(tokens[tokenNumber], APPROVE_SELECTOR, abi.encode(cowswap, allowance));
        erc20Vault.externalCall(cowswap, SET_PRESIGNATURE_SELECTOR, abi.encode(uuid, signed));
    }

    function resetCowswapAllowance(uint8 tokenNumber) external {
        erc20Vault.externalCall(tokens[tokenNumber], APPROVE_SELECTOR, abi.encode(cowswap, 0));
    }

    /// @notice Collect Uniswap pool fees to erc20 vault
    function collectUniFees() external {
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
        fromVault.pull(address(toVault), tokens, tokenAmounts, _makeUniswapVaultOptions(minTokensAmounts, deadline));
    }

    function rebalanceERC20UniV3Vaults() external {
        uint256 linearLiquidityDelta;
        bool isNegativeLinearLiquidityDelta;
        uint256 priceX96 = _priceX96FromTick(targetTick());
        uint256 erc20VaultLinearLiquidity = _getLinearLiquidity(priceX96, erc20Vault);
        uint256 lowerVaultLinearLiquidity = _getLinearLiquidity(priceX96, lowerVault);
        uint256 upperVaultLinearLiquidity = _getLinearLiquidity(priceX96, upperVault);
        (linearLiquidityDelta, isNegativeLinearLiquidityDelta) = _liquidityDelta(
            erc20VaultLinearLiquidity,
            lowerVaultLinearLiquidity + upperVaultLinearLiquidity,
            ratioParams.erc20UniV3RatioD
        );
        (, , uint128 lowerVaultLiquidity) = _getVaultStats(lowerVault);
        (, , uint128 upperVaultLiquidity) = _getVaultStats(upperVault);
        (uint256[] memory lowerVaultTvl, ) = lowerVault.tvl();
        (uint256[] memory upperVaultTvl, ) = upperVault.tvl();
        uint256 uniLiquidityRatio = FullMath.mulDiv(
            lowerVaultLinearLiquidity,
            lowerVaultLinearLiquidity + upperVaultLinearLiquidity,
            DENOMINATOR
        );
        // uint256 lowerVaultLiquidityDeltaRatioD = FullMath.mulDiv(a, b, denominator);
        // if (isNegativeLinearLiquidityDelta) {}
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
        (uint256 targetUniV3LiquidityRatioD, bool isNegativeLiquidityRatio) = targetUniV3LiquidityRatio();
        // // we crossed the interval right to left
        if (isNegativeLiquidityRatio) {
            // pull all liquidity to other vault and swap intervals
            _rebalanceUniV3Liquidity(
                upperVault,
                lowerVault,
                type(uint128).max,
                minWithdrawTokens,
                minDepositTokens,
                deadline
            );
            _swapVaults(false, deadline);
            return;
        }
        // we crossed the interval left to right
        if (targetUniV3LiquidityRatioD > DENOMINATOR) {
            // pull all liquidity to other vault and swap intervals
            _rebalanceUniV3Liquidity(
                lowerVault,
                upperVault,
                type(uint128).max,
                minWithdrawTokens,
                minDepositTokens,
                deadline
            );
            _swapVaults(true, deadline);
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
    /// @return Vault liquidity = x * p + y
    function _getLinearLiquidity(uint256 priceX96, IVault vault) internal view returns (uint256) {
        (uint256[] memory tvl, ) = vault.tvl();
        return FullMath.mulDiv(tvl[0], priceX96, CommonLibrary.Q96) + tvl[1];
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
    /// @param liquidity The amount of liquidity. On overflow best effort pull is made
    /// @param minWithdrawTokens Min accepted tokenAmounts for withdrawal
    /// @param minDepositTokens Min accepted tokenAmounts for deposit
    /// @param deadline Timestamp after which the transaction reverts
    /// @return pulledAmounts amounts pulled from fromVault
    /// @return pushedAmounts amounts pushed to toVault
    function _rebalanceUniV3Liquidity(
        IUniV3Vault fromVault,
        IUniV3Vault toVault,
        uint128 liquidity,
        uint256[] memory minWithdrawTokens,
        uint256[] memory minDepositTokens,
        uint256 deadline
    ) internal returns (uint256[] memory pulledAmounts, uint256[] memory pushedAmounts) {
        address[] memory tokens_ = tokens;
        uint256[] memory withdrawTokenAmounts = fromVault.liquidityToTokenAmounts(liquidity);
        (, , uint128 fromVaultLiquidity) = _getVaultStats(fromVault);
        pulledAmounts = fromVault.pull(
            address(erc20Vault),
            tokens_,
            withdrawTokenAmounts,
            _makeUniswapVaultOptions(minWithdrawTokens, deadline)
        );
        // Approximately `liquidity` will be pulled unless `liquidity` is more than total liquidity in the vault
        uint128 actualLiqudity = fromVaultLiquidity > liquidity ? liquidity : fromVaultLiquidity;
        uint256[] memory depositTokenAmounts = toVault.liquidityToTokenAmounts(actualLiqudity);
        pushedAmounts = erc20Vault.pull(
            address(toVault),
            tokens_,
            depositTokenAmounts,
            _makeUniswapVaultOptions(minDepositTokens, deadline)
        );
        emit RebalancedUniV3(address(fromVault), address(toVault), pulledAmounts, pushedAmounts, liquidity);
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
    /// @param liquidity The amount of liquidity. On overflow best effort pull is made
    event RebalancedUniV3(
        address fromVault,
        address toVault,
        uint256[] pulledAmounts,
        uint256[] pushedAmounts,
        uint128 liquidity
    );
}
