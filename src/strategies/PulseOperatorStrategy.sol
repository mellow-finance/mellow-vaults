// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "../interfaces/adapters/IAdapter.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/TickMath.sol";

import "../utils/DefaultAccessControlLateInit.sol";

import "../strategies/BaseAmmStrategy.sol";

contract PulseOperatorStrategy is DefaultAccessControlLateInit {
    struct ImmutableParams {
        int24 tickSpacing;
        BaseAmmStrategy strategy;
    }

    struct MutableParams {
        int24 intervalWidth;
        int24 maxIntervalWidth;
        uint256 extensionFactorD;
        uint256 neighborhoodFactorD;
    }

    struct VolatileParams {
        bool forceRebalanceFlag;
    }

    struct Storage {
        ImmutableParams immutableParams;
        MutableParams mutableParams;
        VolatileParams volatileParams;
    }

    bytes32 public constant STORAGE_SLOT = keccak256("strategy.storage");
    uint256 public constant D9 = 1e9;
    uint256 public constant Q96 = 2**96;

    function _contractStorage() internal pure returns (Storage storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    function updateMutableParams(MutableParams memory mutableParams) external {
        _requireAdmin();
        if (mutableParams.maxIntervalWidth < mutableParams.intervalWidth) revert(ExceptionsLibrary.INVALID_LENGTH);
        Storage storage s = _contractStorage();
        int24 tickSpacing = s.immutableParams.tickSpacing;
        if (mutableParams.intervalWidth % tickSpacing != 0 || mutableParams.maxIntervalWidth % tickSpacing != 0) {
            revert(ExceptionsLibrary.INVALID_LENGTH);
        }
        if (mutableParams.neighborhoodFactorD > D9) {
            revert(ExceptionsLibrary.LIMIT_OVERFLOW);
        }

        s.mutableParams = mutableParams;
    }

    function setForceRebalanceFlag(bool flag) external {
        _requireAdmin();
        _contractStorage().volatileParams.forceRebalanceFlag = flag;
    }

    function getMutableParams() public view returns (MutableParams memory) {
        return _contractStorage().mutableParams;
    }

    function getImmutableParams() public view returns (ImmutableParams memory) {
        return _contractStorage().immutableParams;
    }

    function getVolatileParams() public view returns (VolatileParams memory) {
        return _contractStorage().volatileParams;
    }

    function initialize(
        ImmutableParams memory immutableParams,
        MutableParams memory mutableParams,
        address admin
    ) external {
        _contractStorage().immutableParams = immutableParams;
        _contractStorage().mutableParams = mutableParams;
        _contractStorage().volatileParams.forceRebalanceFlag = true;
        DefaultAccessControlLateInit(address(this)).init(admin);
    }

    function rebalance(BaseAmmStrategy.SwapData calldata swapData) external {
        _requireAtLeastOperator();
        (BaseAmmStrategy.Position memory newPosition, bool neededNewInterval) = calculateExpectedPosition();
        if (!neededNewInterval) return;
        Storage memory s = _contractStorage();
        ImmutableParams memory immutableParams = s.immutableParams;
        BaseAmmStrategy.Position[] memory targetState = new BaseAmmStrategy.Position[](
            immutableParams.strategy.getImmutableParams().ammVaults.length
        );
        targetState[0] = newPosition;
        targetState[0].capitalRatioX96 = Q96;
        immutableParams.strategy.rebalance(targetState, swapData);
        if (s.volatileParams.forceRebalanceFlag) {
            _contractStorage().volatileParams.forceRebalanceFlag = false;
        }
    }

    function formPositionWithSpotTickInCenter(
        MutableParams memory mutableParams,
        int24 spotTick,
        int24 tickSpacing
    ) public pure returns (BaseAmmStrategy.Position memory newInterval) {
        if (mutableParams.intervalWidth == tickSpacing) {
            newInterval.tickLower = spotTick;
        } else {
            newInterval.tickLower = spotTick - mutableParams.intervalWidth / 2;
        }
        int24 remainder = newInterval.tickLower % tickSpacing;
        if (remainder < 0) remainder += tickSpacing;
        newInterval.tickLower -= remainder;
        newInterval.tickUpper = newInterval.tickLower + mutableParams.intervalWidth;
    }

    function calculateTargetRatioOfToken1(
        BaseAmmStrategy.Position memory position,
        uint160 sqrtRatioX96,
        uint256 priceX96
    ) public pure returns (uint256) {
        (uint256 ratio0X96, uint256 ratio1X96) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(position.tickLower),
            TickMath.getSqrtRatioAtTick(position.tickUpper),
            uint128(Q96)
        );
        uint256 targetCapital = FullMath.mulDiv(ratio0X96, priceX96, Q96) + ratio1X96;
        return FullMath.mulDiv(ratio1X96, Q96, targetCapital);
    }

    function calculateSwapAmounts(address rootVault)
        external
        view
        returns (
            address tokenIn,
            uint256 amountIn,
            address tokenOut,
            uint256 expectedAmountOut
        )
    {
        (BaseAmmStrategy.Position memory position, bool neededNewInterval) = calculateExpectedPosition();
        if (!neededNewInterval) {
            return (tokenIn, amountIn, tokenOut, expectedAmountOut);
        }
        BaseAmmStrategy.ImmutableParams memory baseStrategyImmutableParams = getImmutableParams()
            .strategy
            .getImmutableParams();
        IAdapter adapter = baseStrategyImmutableParams.adapter;
        (uint160 sqrtRatioX96, ) = adapter.slot0(baseStrategyImmutableParams.pool);
        uint256 priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);
        uint256 targetRatioX96 = calculateTargetRatioOfToken1(position, sqrtRatioX96, priceX96);

        (uint256[] memory tvl, ) = IVault(rootVault).tvl();
        uint256 capital = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];
        uint256 currentRatioX96 = FullMath.mulDiv(tvl[1], Q96, capital);
        address[] memory tokens = IVault(rootVault).vaultTokens();
        if (targetRatioX96 < currentRatioX96) {
            amountIn = FullMath.mulDiv(currentRatioX96 - targetRatioX96, capital, Q96);
            tokenIn = tokens[1];
            tokenOut = tokens[0];
            expectedAmountOut = FullMath.mulDiv(amountIn, Q96, priceX96);
        } else {
            amountIn = FullMath.mulDiv(targetRatioX96 - currentRatioX96, capital, priceX96);
            tokenIn = tokens[0];
            tokenOut = tokens[1];
            expectedAmountOut = FullMath.mulDiv(amountIn, priceX96, Q96);
        }
    }

    function calculateExpectedPosition()
        public
        view
        returns (BaseAmmStrategy.Position memory newInterval, bool neededNewInterval)
    {
        MutableParams memory mutableParams = getMutableParams();
        ImmutableParams memory immutableParams = getImmutableParams();
        BaseAmmStrategy.ImmutableParams memory baseStrategyImmutableParams = immutableParams
            .strategy
            .getImmutableParams();
        IAdapter adapter = baseStrategyImmutableParams.adapter;
        IIntegrationVault ammVault = baseStrategyImmutableParams.ammVaults[0];
        BaseAmmStrategy.Position memory currentPosition;
        uint256 tokenId = adapter.tokenId(address(ammVault));
        if (tokenId != 0) {
            (currentPosition.tickLower, currentPosition.tickUpper, ) = adapter.positionInfo(tokenId);
        }
        (, int24 spotTick) = adapter.slot0(baseStrategyImmutableParams.pool);
        return
            _calculateNewInterval(
                currentPosition,
                immutableParams,
                mutableParams,
                getVolatileParams(),
                spotTick,
                tokenId
            );
    }

    function _calculateNewInterval(
        BaseAmmStrategy.Position memory currentPosition,
        ImmutableParams memory immutableParams,
        MutableParams memory mutableParams,
        VolatileParams memory volatileParams,
        int24 spotTick,
        uint256 tokenId
    ) private pure returns (BaseAmmStrategy.Position memory newInterval, bool neededNewInterval) {
        int24 tickSpacing = immutableParams.tickSpacing;
        if (tokenId == 0 || volatileParams.forceRebalanceFlag) {
            return (formPositionWithSpotTickInCenter(mutableParams, spotTick, tickSpacing), true);
        }

        int24 width = currentPosition.tickUpper - currentPosition.tickLower;

        int24 currentNeighborhood = int24(
            uint24(FullMath.mulDiv(uint24(width), mutableParams.neighborhoodFactorD, D9))
        );

        int24 minAcceptableTick = currentPosition.tickLower + currentNeighborhood;
        int24 maxAcceptableTick = currentPosition.tickUpper - currentNeighborhood;
        if (minAcceptableTick <= spotTick && spotTick <= maxAcceptableTick) {
            return (currentPosition, false);
        }

        int24 closeness = minAcceptableTick - spotTick;
        if (spotTick - maxAcceptableTick > closeness) {
            closeness = spotTick - maxAcceptableTick;
        }

        int24 sideExtension = closeness +
            int24(int256(FullMath.mulDiv(uint24(currentNeighborhood), mutableParams.extensionFactorD, D9)));
        if (sideExtension % tickSpacing != 0 || sideExtension == 0) {
            sideExtension += tickSpacing;
            sideExtension -= sideExtension % tickSpacing;
        }

        newInterval.tickLower = currentPosition.tickLower - sideExtension;
        newInterval.tickUpper = currentPosition.tickUpper + sideExtension;

        if (newInterval.tickUpper - newInterval.tickLower > mutableParams.maxIntervalWidth) {
            return (formPositionWithSpotTickInCenter(mutableParams, spotTick, tickSpacing), true);
        }

        neededNewInterval = true;
    }
}
