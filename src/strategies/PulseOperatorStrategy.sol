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
        int24 positionWidth;
        int24 maxPositionWidth;
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
        validateMutableParams(mutableParams);
        _contractStorage().mutableParams = mutableParams;
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
        if (address(immutableParams.strategy) == address(0)) revert(ExceptionsLibrary.ADDRESS_ZERO);
        if (immutableParams.tickSpacing == 0) revert(ExceptionsLibrary.VALUE_ZERO);
        _contractStorage().immutableParams = immutableParams;
        validateMutableParams(mutableParams);
        _contractStorage().mutableParams = mutableParams;
        _contractStorage().volatileParams.forceRebalanceFlag = true;
        DefaultAccessControlLateInit(address(this)).init(admin);
    }

    function rebalance(BaseAmmStrategy.SwapData calldata swapData) external {
        _requireAtLeastOperator();
        (BaseAmmStrategy.Position memory newPosition, bool neededNewPosition) = calculateExpectedPosition();
        if (!neededNewPosition) return;
        Storage memory s = _contractStorage();
        BaseAmmStrategy.Position[] memory targetState = new BaseAmmStrategy.Position[](
            s.immutableParams.strategy.getImmutableParams().ammVaults.length
        );
        targetState[0] = newPosition;
        targetState[0].capitalRatioX96 = Q96;
        s.immutableParams.strategy.rebalance(targetState, swapData);
        if (s.volatileParams.forceRebalanceFlag) {
            _contractStorage().volatileParams.forceRebalanceFlag = false;
        }
    }

    function validateMutableParams(MutableParams memory mutableParams) public view {
        if (mutableParams.maxPositionWidth < mutableParams.positionWidth) revert(ExceptionsLibrary.INVALID_LENGTH);
        Storage storage s = _contractStorage();
        int24 tickSpacing = s.immutableParams.tickSpacing;
        if (
            mutableParams.positionWidth % tickSpacing != 0 ||
            mutableParams.maxPositionWidth % tickSpacing != 0 ||
            mutableParams.positionWidth == 0 ||
            mutableParams.positionWidth > mutableParams.maxPositionWidth
        ) {
            revert(ExceptionsLibrary.INVALID_LENGTH);
        }
        if (mutableParams.neighborhoodFactorD > D9) {
            revert(ExceptionsLibrary.LIMIT_OVERFLOW);
        }
    }

    function _max(int24 a, int24 b) private pure returns (int24) {
        if (a < b) return b;
        return a;
    }

    function formPositionWithSpotTickInCenter(
        int24 positionWidth,
        int24 spotTick,
        int24 tickSpacing
    ) public pure returns (BaseAmmStrategy.Position memory position) {
        position.tickLower = spotTick - positionWidth / 2;
        int24 remainder = position.tickLower % tickSpacing;
        if (remainder < 0) remainder += tickSpacing;
        position.tickLower -= remainder;
        position.tickUpper = position.tickLower + positionWidth;
        if (
            position.tickUpper < spotTick ||
            _max(spotTick - position.tickLower, position.tickUpper - spotTick) >
            _max(spotTick - (position.tickLower + tickSpacing), (position.tickUpper + tickSpacing) - spotTick)
        ) {
            position.tickLower += tickSpacing;
            position.tickUpper += tickSpacing;
        }
    }

    function calculateExpectedPosition()
        public
        view
        returns (BaseAmmStrategy.Position memory newPosition, bool neededNewPosition)
    {
        ImmutableParams memory immutableParams = getImmutableParams();
        BaseAmmStrategy.ImmutableParams memory baseStrategyImmutableParams = immutableParams
            .strategy
            .getImmutableParams();
        IAdapter adapter = baseStrategyImmutableParams.adapter;
        IIntegrationVault ammVault = baseStrategyImmutableParams.ammVaults[0];
        uint256 tokenId = adapter.tokenId(address(ammVault));
        BaseAmmStrategy.Position memory currentPosition;
        if (tokenId != 0) {
            (currentPosition.tickLower, currentPosition.tickUpper, ) = adapter.positionInfo(tokenId);
        }
        (, int24 spotTick) = adapter.slot0(baseStrategyImmutableParams.pool);
        return _calculateNewPosition(currentPosition, immutableParams.tickSpacing, spotTick, tokenId);
    }

    function _calculateNewPosition(
        BaseAmmStrategy.Position memory currentPosition,
        int24 tickSpacing,
        int24 spotTick,
        uint256 tokenId
    ) private view returns (BaseAmmStrategy.Position memory newPosition, bool neededNewPosition) {
        MutableParams memory mutableParams = getMutableParams();
        VolatileParams memory volatileParams = getVolatileParams();
        if (tokenId == 0 || volatileParams.forceRebalanceFlag) {
            return (formPositionWithSpotTickInCenter(mutableParams.positionWidth, spotTick, tickSpacing), true);
        }

        int24 width = currentPosition.tickUpper - currentPosition.tickLower;

        int24 currentNeighborhood = int24(
            uint24(FullMath.mulDiv(uint24(width), mutableParams.neighborhoodFactorD, D9))
        );

        int24 minAcceptableTick = currentPosition.tickLower + currentNeighborhood;
        int24 maxAcceptableTick = currentPosition.tickUpper - currentNeighborhood;
        if (
            minAcceptableTick <= spotTick &&
            spotTick <= maxAcceptableTick &&
            width <= mutableParams.maxPositionWidth &&
            width >= mutableParams.positionWidth
        ) {
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

        newPosition.tickLower = currentPosition.tickLower - sideExtension;
        newPosition.tickUpper = currentPosition.tickUpper + sideExtension;

        if (newPosition.tickUpper - newPosition.tickLower > mutableParams.maxPositionWidth) {
            return (formPositionWithSpotTickInCenter(mutableParams.positionWidth, spotTick, tickSpacing), true);
        }

        neededNewPosition = true;
    }
}
