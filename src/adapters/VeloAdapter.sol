// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/adapters/IAdapter.sol";

import "../interfaces/vaults/IVeloVault.sol";

import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/CommonLibrary.sol";

/*
    VeloAdapter is an adapter contract for VeloVault, designed to handle:
        - Position creation
        - Position updates within the Vault
        - Reward and fee collection
        - Pool price retrieval
        - Detection of MEV manipulations within pools

    It is recommended that all mutable functions are accessed by external contracts using delegatecall.
*/
contract VeloAdapter is IAdapter {
    error InvalidParams();
    error PriceManipulationDetected();
    error NotEnoughObservations();

    using SafeERC20 for IERC20;

    /// @dev Parameters for protection against MEV manipulations
    /// @param lookback - total number of deltas involved in the analysis
    /// @param maxAllowedDelta - maximum allowed delta
    struct SecurityParams {
        uint16 lookback;
        int24 maxAllowedDelta;
    }

    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 1e9;

    INonfungiblePositionManager public immutable positionManager;

    constructor(INonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
    }

    /// @dev This function creates a position with selected ticks and liquidity for a specified pool.
    /// @param poolAddress The address of the pool where the position will be created.
    /// @param tickLower The lower tick of the position.
    /// @param tickUpper The upper tick of the position.
    /// @param liquidity The amount of liquidity to be provided for the position.
    /// @param recipient The address that will become the owner of the created position.
    function mint(
        address poolAddress,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address recipient
    ) external returns (uint256 tokenId_) {
        ICLPool pool = ICLPool(poolAddress);
        (uint160 sqrtRatioX96, , , , , ) = pool.slot0();

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );

        IERC20(pool.token0()).safeIncreaseAllowance(address(positionManager), amount0);
        IERC20(pool.token1()).safeIncreaseAllowance(address(positionManager), amount1);

        (tokenId_, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                tickSpacing: pool.tickSpacing(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max,
                recipient: recipient
            })
        );

        IERC20(pool.token0()).safeApprove(address(positionManager), 0);
        IERC20(pool.token1()).safeApprove(address(positionManager), 0);
    }

    /// @dev This function swaps an empty position in the Vault for a new position with the ID equal to newNft.
    /// @param from The address from which the empty position is being swapped.
    /// @param vault The address of the Vault contract.
    /// @param newNft The ID of the new position.
    function swapNft(
        address from,
        address vault,
        uint256 newNft
    ) external returns (uint256 oldNft) {
        oldNft = IVeloVault(vault).tokenId();
        positionManager.safeTransferFrom(from, vault, newNft);
        if (oldNft != 0) {
            positionManager.burn(oldNft);
        }
    }

    /// @dev This function collects rewards from the Vault.
    /// @param vault The address of the Vault contract.
    function compound(address vault) external {
        IVeloVault(vault).collectRewards();
    }

    /// @dev This function returns information about the ticks and liquidity for a position based on its ID.
    /// @param tokenId_ The ID of the position.
    /// @return tickLower The lower tick of the position.
    /// @return tickUpper The upper tick of the position.
    /// @return liquidity The amount of liquidity in the position.
    function positionInfo(uint256 tokenId_)
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        if (tokenId_ != 0) {
            (, , , , , tickLower, tickUpper, liquidity, , , , ) = positionManager.positions(tokenId_);
        }
    }

    /// @dev This function returns the ID of the position for the Vault.
    /// @param vault The address of the Vault contract.
    /// @return The ID of the position.
    function tokenId(address vault) external view returns (uint256) {
        return IVeloVault(vault).tokenId();
    }

    /// @dev This function returns information about the spot price, additionally checking the pool for MEV manipulations.
    ///      If there are not enough observations in the pool's observations array, the function reverts with error NotEnoughObservations.
    ///      If the price is manipulated, the function reverts with error PriceManipulationDetected.
    /// @param poolAddress The address of the pool.
    /// @param params security parameters (optional).
    /// @return sqrtPriceX96 The square root price of the token0/token1 pair.
    /// @return spotTick The current tick of the pool.
    function slot0EnsureNoMEV(address poolAddress, bytes memory params)
        external
        view
        returns (uint160 sqrtPriceX96, int24 spotTick)
    {
        if (params.length == 0) return slot0(poolAddress);
        uint16 observationIndex;
        uint16 observationCardinality;
        (sqrtPriceX96, spotTick, observationIndex, observationCardinality, , ) = ICLPool(poolAddress).slot0();
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        uint16 lookback = securityParams.lookback;
        if (observationCardinality < lookback + 1) revert NotEnoughObservations();

        (uint32 nextTimestamp, int56 nextCumulativeTick, , ) = ICLPool(poolAddress).observations(observationIndex);
        int24 nextTick = spotTick;
        for (uint16 i = 1; i <= lookback; i++) {
            uint256 index = (observationCardinality + observationIndex - i) % observationCardinality;
            (uint32 timestamp, int56 tickCumulative, , bool initialized) = ICLPool(poolAddress).observations(index);
            if (!initialized) revert NotEnoughObservations();
            int24 tick = int24((nextCumulativeTick - tickCumulative) / int56(uint56(nextTimestamp - timestamp)));
            (nextTimestamp, nextCumulativeTick) = (timestamp, tickCumulative);
            int24 delta = nextTick - tick;
            if (delta < 0) delta = -delta;
            if (delta > securityParams.maxAllowedDelta) revert PriceManipulationDetected();
            nextTick = tick;
        }
    }

    /// @dev This function returns information about the price as follows:
    ///      1. If no swaps were made in the current block, it returns the spot price.
    ///      2. Otherwise, it returns the last price from the observations array.
    ///      In the absence of inter-block price manipulation, the returned price is considered unmanipulated.
    ///      If there are not enough observations in the pool's observations array, the function reverts with error NotEnoughObservations.
    /// @param pool The address of the pool.
    /// @return The square root price of the token0/token1 pair.
    /// @return The current tick of the pool.
    function getOraclePrice(address pool) external view override returns (uint160, int24) {
        (
            uint160 spotSqrtPriceX96,
            int24 spotTick,
            uint16 observationIndex,
            uint16 observationCardinality,
            ,

        ) = ICLPool(pool).slot0();
        if (observationCardinality < 2) revert NotEnoughObservations();
        (uint32 blockTimestamp, int56 tickCumulative, , ) = ICLPool(pool).observations(observationIndex);
        if (block.timestamp != blockTimestamp) return (spotSqrtPriceX96, spotTick);
        uint16 previousObservationIndex = observationCardinality - 1;
        if (observationIndex != 0) previousObservationIndex = observationIndex - 1;
        if (previousObservationIndex == observationCardinality) revert NotEnoughObservations();
        (uint32 previousBlockTimestamp, int56 previousTickCumulative, , ) = ICLPool(pool).observations(
            previousObservationIndex
        );
        int56 tickCumulativesDelta = tickCumulative - previousTickCumulative;
        int24 tick = int24(tickCumulativesDelta / int56(uint56(blockTimestamp - previousBlockTimestamp)));
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        return (sqrtPriceX96, tick);
    }

    /// @dev This function returns information about the spot price.
    ///      There is no protection against manipulations in this function.
    /// @param poolAddress The address of the pool.
    /// @return sqrtPriceX96 The square root price of the token0/token1 pair.
    /// @return spotTick The current tick of the pool.
    function slot0(address poolAddress) public view returns (uint160 sqrtPriceX96, int24 spotTick) {
        (sqrtPriceX96, spotTick, , , , ) = ICLPool(poolAddress).slot0();
    }

    /// @dev Function for validating parameters for MEV protection.
    /// @param params The parameters to validate.
    function validateSecurityParams(bytes memory params) external pure {
        if (params.length == 0) return;
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        if (securityParams.lookback == 0 || securityParams.maxAllowedDelta < 0) revert InvalidParams();
    }
}
