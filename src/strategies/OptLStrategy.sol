// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/ExceptionsLibrary.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";

import "../utils/DefaultAccessControl.sol";

contract OptLStrategy is DefaultAccessControl {
    struct ImmutableParams {
        int24 width;
        uint24 fee;
        IERC20Vault erc20Vault;
        IUniV3Vault lowerVault;
        IUniV3Vault upperVault;
        IUniswapV3Pool pool;
        address router;
        address[] tokens;
    }

    struct MutableParams {
        uint32 timespan;
        int24 maxTickDeviation;
        uint256 maxRatioDeviationX96;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 swapSlippageD;
        uint256 swappingAmountsCoefficientD;
        uint256[] minSwapAmounts;
    }

    struct Storage {
        ImmutableParams immutableParams;
        MutableParams mutableParams;
    }

    bytes32 public constant STORAGE_POSITION = keccak256("strategy.storage");
    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 1e9;

    INonfungiblePositionManager public immutable positionManager;

    function _contractStorage() internal pure returns (Storage storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    constructor(address admin, INonfungiblePositionManager positionManager_) DefaultAccessControl(admin) {
        positionManager = positionManager_;
    }

    function updateMutableParams(MutableParams memory newMutableParams) external {
        _requireAdmin();
        _contractStorage().mutableParams = newMutableParams;
    }

    function _pushMissing(
        IUniV3Vault to,
        ImmutableParams memory immutableParams,
        uint128 targetLiquidity
    ) private {
        uint256[] memory tokenAmounts = to.liquidityToTokenAmounts(targetLiquidity);
        (uint256[] memory actualAmounts, ) = to.tvl();
        bool needToPush = false;
        for (uint256 i = 0; i < 2; i++) {
            if (tokenAmounts[i] > actualAmounts[i]) {
                tokenAmounts[i] -= actualAmounts[i];
                needToPush = true;
            } else {
                tokenAmounts[i] = 0;
            }
        }
        if (!needToPush) return;
        immutableParams.erc20Vault.pull(address(to), immutableParams.tokens, tokenAmounts, "");
    }

    function _drainExtra(
        IUniV3Vault from,
        ImmutableParams memory immutableParams,
        uint128 targetLiquidity
    ) private {
        uint256[] memory tokenAmounts = from.liquidityToTokenAmounts(targetLiquidity);
        (uint256[] memory actualAmounts, ) = from.tvl();
        bool needToDrain = false;
        for (uint256 i = 0; i < 2; i++) {
            if (tokenAmounts[i] < actualAmounts[i]) {
                tokenAmounts[i] = actualAmounts[i] - tokenAmounts[i];
                needToDrain = true;
            } else {
                tokenAmounts[i] = 0;
            }
        }
        if (!needToDrain) return;
        from.pull(address(immutableParams.erc20Vault), immutableParams.tokens, tokenAmounts, "");
    }

    function _drain(
        IUniV3Vault from,
        ImmutableParams memory immutableParams,
        uint128 liquidity
    ) private {
        uint256[] memory tokenAmounts = from.liquidityToTokenAmounts(liquidity);
        from.pull(address(immutableParams.erc20Vault), immutableParams.tokens, tokenAmounts, "");
    }

    function _drainAndMint(
        Storage memory s,
        IUniV3Vault vault,
        int24 lowerTick,
        int24 upperTick
    ) private {
        uint256 oldNft = vault.uniV3Nft();
        if (oldNft != 0) _drain(vault, s.immutableParams, type(uint128).max);
        IUniswapV3Pool pool = s.immutableParams.pool;
        (uint256 newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: pool.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: s.mutableParams.amount0Desired,
                amount1Desired: s.mutableParams.amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );
        positionManager.safeTransferFrom(address(this), address(vault), newNft);
        if (oldNft != 0) positionManager.burn(oldNft);
    }

    function rebalance(
        bytes calldata swapData,
        uint256 minAmountOutInCaseOfSwap,
        uint256 deadline
    ) external {
        if (block.timestamp > deadline) revert(ExceptionsLibrary.TIMESTAMP);
        _requireAtLeastOperator();
        (uint256 expectedRatioX96, int24 expectedLowerTick) = getCurrentState();
        Storage memory s = _contractStorage();
        {
            (uint256 currentRatioX96, int24 currentLowerTick) = calculateExpectedState();
            if (currentLowerTick == expectedLowerTick) {
                uint256 maxRatioDeviationX96 = s.mutableParams.maxRatioDeviationX96;
                if (
                    currentRatioX96 + maxRatioDeviationX96 >= expectedRatioX96 &&
                    expectedRatioX96 + maxRatioDeviationX96 >= currentRatioX96
                ) {
                    // nothing to rebalance
                    return;
                }
            } else {
                int24 width = s.immutableParams.width;
                IUniV3Vault lowerVault = s.immutableParams.lowerVault;
                IUniV3Vault upperVault = s.immutableParams.upperVault;
                if (expectedLowerTick == currentLowerTick + width) {
                    _drainAndMint(s, lowerVault, expectedLowerTick + width, expectedLowerTick + width * 3);
                    (lowerVault, upperVault) = (upperVault, lowerVault);
                    currentRatioX96 = Q96 - currentRatioX96;
                } else if (expectedLowerTick + width == currentLowerTick) {
                    _drainAndMint(s, upperVault, expectedLowerTick, expectedLowerTick + width * 2);
                    (lowerVault, upperVault) = (upperVault, lowerVault);
                    currentRatioX96 = Q96 - currentRatioX96;
                } else {
                    _drainAndMint(s, lowerVault, expectedLowerTick, expectedLowerTick + width * 2);
                    _drainAndMint(s, upperVault, expectedLowerTick + width, expectedLowerTick + width * 3);
                }
                s.immutableParams.lowerVault = lowerVault;
                s.immutableParams.upperVault = upperVault;
                _contractStorage().immutableParams = s.immutableParams;
            }
        }

        (
            uint128 expectedLowerLiquidity,
            uint128 expectedUpperLiquidity,
            uint256 tokenInIndex,
            uint256 amountIn
        ) = calculateExpectedParameters(s, expectedRatioX96);

        _drainExtra(s.immutableParams.lowerVault, s.immutableParams, expectedLowerLiquidity);
        _drainExtra(s.immutableParams.upperVault, s.immutableParams, expectedUpperLiquidity);
        _swap(s, tokenInIndex, amountIn, minAmountOutInCaseOfSwap, swapData);
        _pushMissing(s.immutableParams.lowerVault, s.immutableParams, expectedLowerLiquidity);
        _pushMissing(s.immutableParams.upperVault, s.immutableParams, expectedUpperLiquidity);
    }

    function _swap(
        Storage memory s,
        uint256 tokenInIndex,
        uint256 amountIn,
        uint256 minAmountOutInCaseOfSwap,
        bytes calldata swapData
    ) private {
        if (amountIn < s.mutableParams.minSwapAmounts[tokenInIndex]) {
            return;
        }
        (uint160 sqrtPriceX96, , , , , , ) = s.immutableParams.pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (tokenInIndex == 1) priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);

        (uint256[] memory tvlBefore, ) = s.immutableParams.erc20Vault.tvl();

        s.immutableParams.erc20Vault.externalCall(s.immutableParams.router, bytes4(swapData[:4]), swapData[4:]);

        uint256 actualAmountIn;
        uint256 actualAmountOut;
        {
            (uint256[] memory tvlAfter, ) = s.immutableParams.erc20Vault.tvl();

            require(tvlAfter[tokenInIndex] <= tvlBefore[tokenInIndex], ExceptionsLibrary.INVARIANT);
            require(tvlAfter[tokenInIndex ^ 1] >= tvlBefore[tokenInIndex ^ 1], ExceptionsLibrary.INVARIANT);

            actualAmountIn = tvlBefore[tokenInIndex] - tvlAfter[tokenInIndex];
            actualAmountOut = tvlAfter[tokenInIndex ^ 1] - tvlBefore[tokenInIndex ^ 1];
        }

        uint256 actualSwapPriceX96 = FullMath.mulDiv(actualAmountOut, Q96, actualAmountIn);

        require(actualAmountOut >= minAmountOutInCaseOfSwap, ExceptionsLibrary.LIMIT_UNDERFLOW);

        require(
            FullMath.mulDiv(priceX96, D9 - s.mutableParams.swapSlippageD, D9) <= actualSwapPriceX96,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        require(
            FullMath.mulDiv(amountIn, D9 - s.mutableParams.swappingAmountsCoefficientD, D9) <= actualAmountIn,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        require(
            FullMath.mulDiv(actualAmountIn, D9 - s.mutableParams.swappingAmountsCoefficientD, D9) <= amountIn,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );
    }

    function calculateExpectedParameters(Storage memory s, uint256 expectedRatioX96)
        public
        view
        returns (
            uint128 expectedLowerLiquidity,
            uint128 expectedUpperLiquidity,
            uint256 tokenInIndex,
            uint256 amountIn
        )
    {
        IUniV3Vault lowerVault = s.immutableParams.lowerVault;
        IUniV3Vault upperVault = s.immutableParams.upperVault;
        uint256[] memory tvl = new uint256[](2);
        {
            (uint256[] memory erc20Tvl, ) = s.immutableParams.erc20Vault.tvl();
            (uint256[] memory lowerTvl, ) = lowerVault.tvl();
            (uint256[] memory upperTvl, ) = upperVault.tvl();
            for (uint256 i = 0; i < 2; i++) {
                tvl[i] = erc20Tvl[i] + lowerTvl[i] + upperTvl[i];
            }
        }

        uint256[] memory lowerAmountsQ96 = lowerVault.liquidityToTokenAmounts(uint128(Q96));
        uint256[] memory upperAmountsQ96 = upperVault.liquidityToTokenAmounts(uint128(Q96));
        uint256[] memory weightedAmountsX96 = new uint256[](2);
        {
            for (uint256 i = 0; i < 2; i++) {
                weightedAmountsX96[i] =
                    FullMath.mulDiv(lowerAmountsQ96[i], expectedRatioX96, Q96) +
                    FullMath.mulDiv(upperAmountsQ96[i], Q96 - expectedRatioX96, Q96);
            }
        }
        IUniswapV3Pool pool = s.immutableParams.pool;
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 weightedCapital = FullMath.mulDiv(weightedAmountsX96[0], priceX96, Q96) + weightedAmountsX96[1];
        uint256 capital = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
        uint256 coefficientX96 = FullMath.mulDiv(capital, Q96, weightedCapital);
        for (uint256 i = 0; i < 2; i++) {
            lowerAmountsQ96[i] = FullMath.mulDiv(lowerAmountsQ96[i], coefficientX96, Q96);
            upperAmountsQ96[i] = FullMath.mulDiv(upperAmountsQ96[i], coefficientX96, Q96);
            weightedAmountsX96[i] = lowerAmountsQ96[i] + upperAmountsQ96[i];
        }
        expectedLowerLiquidity = lowerVault.tokenAmountsToLiquidity(lowerAmountsQ96);
        expectedUpperLiquidity = lowerVault.tokenAmountsToLiquidity(upperAmountsQ96);
        if (weightedAmountsX96[0] <= tvl[0] && weightedAmountsX96[1] >= tvl[1]) {
            tokenInIndex = 0;
            amountIn = tvl[0] - weightedAmountsX96[0];
        } else if (weightedAmountsX96[0] >= tvl[0] && weightedAmountsX96[1] <= tvl[1]) {
            tokenInIndex = 1;
            amountIn = tvl[1] - weightedAmountsX96[1];
        }
    }

    function getTickEnsureNoMEV() public view returns (int24 tick) {
        Storage memory s = _contractStorage();
        IUniswapV3Pool pool = s.immutableParams.pool;
        (, int24 spotTick, , , , , ) = pool.slot0();
        bool withFail;
        (tick, , withFail) = OracleLibrary.consult(address(pool), s.mutableParams.timespan);
        if (withFail) revert(ExceptionsLibrary.INVALID_STATE);
        int24 deviation = spotTick - tick;
        if (deviation < 0) deviation = -deviation;
        if (deviation > s.mutableParams.maxTickDeviation) revert(ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function calculateExpectedState() public view returns (uint256 ratioX96, int24 l) {
        int24 w = _contractStorage().immutableParams.width;
        int24 tick = getTickEnsureNoMEV();
        int24 reminder = tick % w;
        if (reminder < 0) reminder += w;
        l = tick - reminder - w;
        ratioX96 = FullMath.mulDiv(Q96, uint24(l + 2 * w - tick), uint24(w));
    }

    function getCurrentState() public view returns (uint256 ratioX96, int24 l) {
        Storage memory s = _contractStorage();
        uint256 lowerNft = s.immutableParams.lowerVault.uniV3Nft();
        if (lowerNft == 0) return (0, type(int24).min);
        uint256 upperNft = s.immutableParams.upperVault.uniV3Nft();
        uint128 lowerLiquidity;
        (, , , , , l, , lowerLiquidity, , , , ) = positionManager.positions(lowerNft);
        (, , , , , , , uint128 upperLiquidity, , , , ) = positionManager.positions(upperNft);
        if (lowerLiquidity + upperLiquidity != 0)
            ratioX96 = FullMath.mulDiv(lowerLiquidity, Q96, lowerLiquidity + upperLiquidity);
    }
}
