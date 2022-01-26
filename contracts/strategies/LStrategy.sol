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

contract LStrategy is Multicall {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint256 public constant DENOMINATOR = 10**9;
    address[] public tokens;
    IERC20Vault public immutable erc20Vault;
    INonfungiblePositionManager public immutable positionManager;
    bool public immutable reversedTokensInPool;
    uint24 public immutable poolFee;

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
    function targetLiquidityRatio() public view returns (uint256 liquidityRatioD, bool isNegative) {
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

    function collectEarnings() external {
        lowerVault.collectEarnings();
        upperVault.collectEarnings();
    }

    function pullFromUniV3Vault(
        IUniV3Vault fromVault,
        uint256[] memory tokenAmounts,
        IUniV3Vault.Options memory withdrawOptions
    ) external {
        fromVault.pull(address(erc20Vault), tokens, tokenAmounts, abi.encode(withdrawOptions));
    }

    function pullFromERC20Vault(
        IUniV3Vault toVault,
        uint256[] memory tokenAmounts,
        IUniV3Vault.Options memory depositOptions
    ) external {
        erc20Vault.pull(address(toVault), tokens, tokenAmounts, abi.encode(depositOptions));
    }

    function rebalanceUniV3Vaults(
        uint256[] memory minWithdrawTokens,
        uint256[] memory minDepositTokens,
        uint256 deadline
    ) external {
        (uint256 targetLiquidityRatioD, bool isNegativeLiquidityRatio) = targetLiquidityRatio();
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
        if (targetLiquidityRatioD > DENOMINATOR) {
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
        (uint128 liquidityDelta, bool isNegativeLiquidityDelta) = _liquidityDelta(
            lowerLiquidity,
            upperLiquidity,
            targetLiquidityRatioD
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
        _rebalanceUniV3Liquidity(fromVault, toVault, liquidityDelta, minWithdrawTokens, minDepositTokens, deadline);
    }

    // -------------------  INTERNAL, VIEW  -------------------

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
        uint128 lowerLiquidity,
        uint128 upperLiquidity,
        uint256 targetLiquidityRatioD
    ) internal pure returns (uint128 delta, bool isNegative) {
        uint128 targetLowerLiquidity = uint128(
            FullMath.mulDiv(targetLiquidityRatioD, uint256(lowerLiquidity + upperLiquidity), DENOMINATOR)
        );
        if (targetLowerLiquidity > lowerLiquidity) {
            isNegative = true;
            delta = targetLowerLiquidity - lowerLiquidity;
        } else {
            isNegative = false;
            delta = lowerLiquidity - targetLowerLiquidity;
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
    function _rebalanceUniV3Liquidity(
        IUniV3Vault fromVault,
        IUniV3Vault toVault,
        uint128 liquidity,
        uint256[] memory minWithdrawTokens,
        uint256[] memory minDepositTokens,
        uint256 deadline
    ) internal {
        address[] memory tokens_ = tokens;
        uint256[] memory withdrawTokenAmounts = fromVault.liquidityToTokenAmounts(liquidity);
        (, , uint128 fromVaultLiquidity) = _getVaultStats(fromVault);
        fromVault.pull(
            address(erc20Vault),
            tokens_,
            withdrawTokenAmounts,
            _makeUniswapVaultOptions(minWithdrawTokens, deadline)
        );
        // Approximately `liquidity` will be pulled unless `liquidity` is more than total liquidity in the vault
        uint128 actualLiqudity = fromVaultLiquidity > liquidity ? liquidity : fromVaultLiquidity;
        uint256[] memory depositTokenAmounts = toVault.liquidityToTokenAmounts(actualLiqudity);
        erc20Vault.pull(
            address(toVault),
            tokens_,
            depositTokenAmounts,
            _makeUniswapVaultOptions(minDepositTokens, deadline)
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

    /// @notice Covert token amounts and deadline to byte options
    /// @dev Empty tokenAmounts are equivalent to zero tokenAmounts
    function _makeUniswapVaultOptions(uint256[] memory tokenAmounts, uint256 deadline)
        internal
        returns (bytes memory options)
    {
        options = new bytes(96);
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

    /// @notice Emitted when vault is swapped.
    /// @param oldNft UniV3 nft that was burned
    /// @param newNft UniV3 nft that was created
    /// @param newTickLower Lower tick for created UniV3 nft
    /// @param newTickUpper Upper tick for created UniV3 nft
    event SwapVault(uint256 oldNft, uint256 newNft, int24 newTickLower, int24 newTickUpper);
}
