// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/oracles/IUniV3Oracle.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/DefaultAccessControl.sol";

contract UniV3Oracle is IContractMeta, IUniV3Oracle, DefaultAccessControl {
    bytes32 public constant CONTRACT_NAME = "UniV3Oracle";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    IUniswapV3Factory public immutable factory;
    uint16 public observationsForAverage;

    constructor(
        IUniswapV3Factory factory_,
        uint16 observationsForAverage_,
        address admin
    ) DefaultAccessControl(admin) {
        factory = factory_;
        observationsForAverage = observationsForAverage_;
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IUniV3Oracle
    function pricesX96(address token0, address token1)
        external
        view
        returns (uint256 spotPriceX96, uint256 avgPriceX96)
    {
        require(token1 > token0, ExceptionsLibrary.INVARIANT);
        address pool = factory.getPool(token0, token1, 3000);
        if (pool == address(0)) {
            pool = factory.getPool(token0, token1, 500);
        }
        if (pool == address(0)) {
            pool = factory.getPool(token0, token1, 10000);
        }
        require(pool != address(0), ExceptionsLibrary.NOT_FOUND);

        (uint256 spotSqrtPriceX96, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(
            pool
        ).slot0();
        uint16 bfAvg = observationsForAverage;
        require(observationCardinality > bfAvg, ExceptionsLibrary.INVALID_VALUE);
        uint256 obs1 = (uint256(observationIndex) + uint256(observationCardinality) - 1) %
            uint256(observationCardinality);
        uint256 obs0 = (uint256(observationIndex) + uint256(observationCardinality) - bfAvg) %
            uint256(observationCardinality);
        (uint32 timestamp0, int56 tick0, , ) = IUniswapV3Pool(pool).observations(obs0);
        (uint32 timestamp1, int56 tick1, , ) = IUniswapV3Pool(pool).observations(obs1);
        uint256 timespan = timestamp1 - timestamp0;
        int256 tickAverage = (int256(tick1) - int256(tick0)) / int256(uint256(timespan));
        uint256 avgSqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24(tickAverage));
        avgPriceX96 = FullMath.mulDiv(avgSqrtPriceX96, avgSqrtPriceX96, CommonLibrary.Q96);
        spotPriceX96 = FullMath.mulDiv(spotSqrtPriceX96, spotSqrtPriceX96, CommonLibrary.Q96);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IUniV3Oracle).interfaceId == interfaceId;
    }

    // -------------------------  EXTERNAL, MUTATING  ------------------------------

    /// @inheritdoc IUniV3Oracle
    function setObservationsForAverage(uint16 newObservationsForAverage) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(observationsForAverage > 1, ExceptionsLibrary.INVALID_VALUE);
        observationsForAverage = newObservationsForAverage;
        emit SetObservationsForAverage(tx.origin, msg.sender, newObservationsForAverage);
    }

    // --------------------------  EVENTS  --------------------------

    event SetObservationsForAverage(address indexed origin, address indexed sender, uint16 observationsForAverage);
}
