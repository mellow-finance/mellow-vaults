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

/*
    Contract of the operator strategy interacting with BaseAmmStrategy. Implements the logic of PulseStrategyV2.
*/
contract PulseOperatorStrategy is DefaultAccessControlLateInit {
    /// @notice This struct contains the immutable parameters of the strategy.
    /// @param tickSpacing The tick spacing of the strategy's pool.
    /// @param strategy The address of the base strategy contract.
    struct ImmutableParams {
        int24 tickSpacing;
        BaseAmmStrategy strategy;
    }

    /// @notice This struct contains the mutable parameters of the strategy.
    /// @param positionWidth The initial position width.
    /// @param maxPositionWidth The maximum position width.
    /// @param extensionFactorD The extension factor, expressed as a fraction of tickNeighborhood.
    /// @param neighborhoodFactorD The factor determining tickNeighborhood as a fraction of position width.
    struct MutableParams {
        int24 positionWidth;
        int24 maxPositionWidth;
        uint256 extensionFactorD;
        uint256 neighborhoodFactorD;
    }

    /// @notice This struct contains the volatile parameters of the strategy.
    /// @param forceRebalanceFlag A flag indicating that if set to true, a new position of width positionWidth will be minted
    /// during the next rebalance.
    struct VolatileParams {
        bool forceRebalanceFlag;
    }

    /// @notice This struct contains the storage with all necessary nested structs for the strategy.
    /// @param immutableParams The immutable parameters of the strategy.
    /// @param mutableParams The mutable parameters of the strategy.
    /// @param volatileParams The volatile parameters of the strategy.
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

    /// @notice This function updates the mutable parameters of the strategy.
    /// @param mutableParams The new mutable parameters to be updated in the strategy.
    /// @dev This function can only be called by an address with the ADMIN_ROLE.
    function updateMutableParams(MutableParams memory mutableParams) external {
        _requireAdmin();
        validateMutableParams(mutableParams);
        _contractStorage().mutableParams = mutableParams;
    }

    /// @notice This function updates the forceRebalanceFlag parameter.
    /// @param flag The new value of the forceRebalanceFlag parameter.
    /// @dev This function can only be called by an address with the ADMIN_ROLE.
    function setForceRebalanceFlag(bool flag) external {
        _requireAdmin();
        _contractStorage().volatileParams.forceRebalanceFlag = flag;
    }

    /// @notice This function retrieves the mutable parameters of the strategy.
    /// @return mutableParams The current mutable parameters of the strategy.
    function getMutableParams() public view returns (MutableParams memory) {
        return _contractStorage().mutableParams;
    }

    /// @notice This function retrieves the immutable parameters of the strategy.
    /// @return immutableParams The immutable parameters of the strategy.
    function getImmutableParams() public view returns (ImmutableParams memory) {
        return _contractStorage().immutableParams;
    }

    /// @notice This function retrieves the volatile parameters of the strategy.
    /// @return volatileParams The volatile parameters of the strategy.
    function getVolatileParams() public view returns (VolatileParams memory) {
        return _contractStorage().volatileParams;
    }

    /// @notice Initializes the strategy with the provided parameters.
    /// @param immutableParams The immutable parameters of the strategy.
    /// @param mutableParams The mutable parameters of the strategy.
    /// @param admin The address to be assigned as the admin of the strategy.
    /// @dev This function performs validation of all parameters and can only be called once.
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

    /// @notice Rebalances the strategy
    /// Can only be called by an address with the ADMIN_ROLE or OPERATOR role.
    /// @param swapData The swap data structure containing information for token swaps.
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

    /// @notice Validates the mutable parameters of the strategy.
    /// @param mutableParams The mutable parameters to be validated.
    /// @dev If the conditions are not met, the function reverts with an error.
    function validateMutableParams(MutableParams memory mutableParams) public view {
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
        if (mutableParams.neighborhoodFactorD * 2 > D9) {
            revert(ExceptionsLibrary.LIMIT_OVERFLOW);
        }
    }

    /// @notice Helper function to get the maximum of two numbers.
    function _max(int24 a, int24 b) private pure returns (int24) {
        if (a < b) return b;
        return a;
    }

    /// @notice Function to form a new position of a given width, centered around the spotTick with respect to tickSpacing.
    /// @param positionWidth The width of the position.
    /// @param spotTick The target tick around which the position will be centered.
    /// @param tickSpacing The tick spacing of the pool.
    /// @return position The newly formed position.
    /// @dev This function returns any position [tickLower, tickUpper] (tickLower % tickSpacing == 0 and tickUpper % tickSpacing == 0)
    /// such that there exists no other position [tickLower2, tickUpper2] where:
    /// max(|spotTick - tickLower2|, |spotTick - tickUpper2|) < max(|spotTick - tickLower|, |spotTick - tickUpper|)
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

    /// @notice Function to calculate the expected position after rebalancing.
    /// @return newPosition The newly expected position after rebalancing.
    /// @return neededNewPosition A boolean indicating whether a new position is needed.
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

    /// @notice Private function to calculate the new expected position after rebalancing.
    /// @dev The logic of this function is as follows:
    ///     1. If there is no position, the forceRebalanceFlag is set, or mutableParams.positionWidth <= width <= mutableParams.positionWidth is not met,
    ///        then a new position is determined using the formPositionWithSpotTickInCenter function with a width of positionWidth.
    ///     2. Otherwise, if the spotTick lies within the interval defined by tickNeighborhood,
    ///        i.e., tickLower + tickNeighborhood <= spotTick <= tickUpper - tickNeigborhood, it is considered
    ///        that rebalancing is not necessary, and the position will not be changed during its process.
    ///     3. Otherwise:
    ///        - The minimum closeness value needed to extend the position evenly on both sides is determined
    ///          to satisfy the condition: tickLower - closeness + tickNeighborhood <= spotTick <= tickUpper + closeness - tickNeigborhood
    ///        - sideExtension is calculated as tickNeighborhood * extensionFactor + closeness
    ///        - Then sideExtension is aligned to tickSpacing
    ///        - Then a new position is formed from the original one, evenly extended on both sides by sideExtension
    ///        - The obtained position from the previous step is the function's answer if it has a width not exceeding maxPositionWidth,
    ///          otherwise, a new position is formed through the formPositionWithSpotTickInCenter function with a width of positionWidth.
    /// @param currentPosition The current position information.
    /// @param tickSpacing The tick spacing of the pool.
    /// @param spotTick The spot tick value.
    /// @param tokenId The ID of the token.
    /// @return newPosition The newly expected position after rebalancing.
    /// @return neededNewPosition A boolean indicating whether a new position is needed.
    function _calculateNewPosition(
        BaseAmmStrategy.Position memory currentPosition,
        int24 tickSpacing,
        int24 spotTick,
        uint256 tokenId
    ) private view returns (BaseAmmStrategy.Position memory newPosition, bool neededNewPosition) {
        MutableParams memory mutableParams = getMutableParams();
        VolatileParams memory volatileParams = getVolatileParams();
        int24 width = currentPosition.tickUpper - currentPosition.tickLower;
        if (
            tokenId == 0 ||
            volatileParams.forceRebalanceFlag ||
            width > mutableParams.maxPositionWidth ||
            width < mutableParams.positionWidth
        ) {
            return (formPositionWithSpotTickInCenter(mutableParams.positionWidth, spotTick, tickSpacing), true);
        }

        int24 currentNeighborhood = int24(
            uint24(FullMath.mulDiv(uint24(width), mutableParams.neighborhoodFactorD, D9))
        );

        int24 minAcceptableTick = currentPosition.tickLower + currentNeighborhood;
        int24 maxAcceptableTick = currentPosition.tickUpper - currentNeighborhood;
        if (minAcceptableTick <= spotTick && spotTick <= maxAcceptableTick) {
            return (currentPosition, false);
        }

        int24 closeness = _max(minAcceptableTick - spotTick, spotTick - maxAcceptableTick);
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
