// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/adapters/IAdapter.sol";

import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";

contract UniswapV3Adapter is IAdapter {
    error InvalidParams();
    error PriceManipulationDetected();
    error NotEnoughObservations();

    using SafeERC20 for IERC20;

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

    function mint(
        address poolAddress,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address recipient
    ) external returns (uint256 tokenId_) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

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
                fee: pool.fee(),
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

    function swapNft(
        address from,
        address vault,
        uint256 newNft
    ) external returns (uint256 oldNft) {
        oldNft = IUniV3Vault(vault).uniV3Nft();
        positionManager.safeTransferFrom(from, vault, newNft);
        if (oldNft != 0) {
            positionManager.burn(oldNft);
        }
    }

    function compound(address vault) external {
        IUniV3Vault(vault).collectEarnings();
    }

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

    function tokenId(address vault) external view returns (uint256) {
        return IUniV3Vault(vault).uniV3Nft();
    }

    function getDeltas(address poolAddress, uint16 lookback) public view returns (int24[] memory deltas) {
        (, int24 spotTick, uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(poolAddress)
            .slot0();
        if (observationCardinality < lookback + 1) revert NotEnoughObservations();

        (uint32 nextTimestamp, int56 nextCumulativeTick, , ) = IUniswapV3Pool(poolAddress).observations(
            observationIndex
        );
        int24 nextTick = spotTick;
        deltas = new int24[](lookback);
        for (uint16 i = 1; i <= lookback; i++) {
            uint256 index = (observationCardinality + observationIndex - i) % observationCardinality;
            (uint32 timestamp, int56 tickCumulative, , ) = IUniswapV3Pool(poolAddress).observations(index);
            int24 tick = int24((nextCumulativeTick - tickCumulative) / int56(uint56(nextTimestamp - timestamp)));
            (nextTimestamp, nextCumulativeTick) = (timestamp, tickCumulative);
            deltas[i - 1] = nextTick - tick;
            nextTick = tick;
        }
    }

    function slot0EnsureNoMEV(address poolAddress, bytes memory params)
        external
        view
        returns (uint160 sqrtPriceX96, int24 spotTick)
    {
        if (params.length == 0) return slot0(poolAddress);
        uint16 observationIndex;
        uint16 observationCardinality;
        (sqrtPriceX96, spotTick, observationIndex, observationCardinality, , , ) = IUniswapV3Pool(poolAddress).slot0();
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        uint16 lookback = securityParams.lookback;
        if (observationCardinality < lookback + 1) revert NotEnoughObservations();

        (uint32 nextTimestamp, int56 nextCumulativeTick, , ) = IUniswapV3Pool(poolAddress).observations(
            observationIndex
        );
        int24 nextTick = spotTick;
        int24 maxAllowedDelta = securityParams.maxAllowedDelta;
        for (uint16 i = 1; i <= lookback; i++) {
            uint256 index = (observationCardinality + observationIndex - i) % observationCardinality;
            (uint32 timestamp, int56 tickCumulative, , ) = IUniswapV3Pool(poolAddress).observations(index);
            int24 tick = int24((nextCumulativeTick - tickCumulative) / int56(uint56(nextTimestamp - timestamp)));
            (nextTimestamp, nextCumulativeTick) = (timestamp, tickCumulative);
            int24 delta = nextTick - tick;
            if (delta > maxAllowedDelta || delta < -maxAllowedDelta) revert PriceManipulationDetected();
            nextTick = tick;
        }
    }

    function getOraclePrice(address pool) external view override returns (uint160, int24) {
        (
            uint160 spotSqrtPriceX96,
            int24 spotTick,
            uint16 observationIndex,
            uint16 observationCardinality,
            ,
            ,

        ) = IUniswapV3Pool(pool).slot0();
        if (observationCardinality < 2) revert NotEnoughObservations();
        (uint32 blockTimestamp, int56 tickCumulative, , ) = IUniswapV3Pool(pool).observations(observationIndex);
        if (block.timestamp != blockTimestamp) return (spotSqrtPriceX96, spotTick);
        uint16 previousObservationIndex = observationCardinality - 1;
        if (observationIndex != 0) previousObservationIndex = observationIndex - 1;
        if (previousObservationIndex == observationCardinality) revert NotEnoughObservations();
        (uint32 previousBlockTimestamp, int56 previousTickCumulative, , ) = IUniswapV3Pool(pool).observations(
            previousObservationIndex
        );
        int56 tickCumulativesDelta = tickCumulative - previousTickCumulative;
        int24 tick = int24(tickCumulativesDelta / int56(uint56(blockTimestamp - previousBlockTimestamp)));
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        return (sqrtPriceX96, tick);
    }

    function slot0(address poolAddress) public view returns (uint160 sqrtPriceX96, int24 spotTick) {
        (sqrtPriceX96, spotTick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();
    }

    function validateSecurityParams(bytes memory params) external pure {
        if (params.length == 0) return;
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        if (securityParams.lookback == 0 || securityParams.maxAllowedDelta < 0) revert InvalidParams();
    }
}
