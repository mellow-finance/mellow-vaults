// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
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
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant CONTRACT_NAME = "UniV3Oracle";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";
    uint16 public constant LOW_OBS = 10; // >= 2.5 min
    uint16 public constant MID_OBS = 30; // >= 7.5 min
    uint16 public constant HIGH_OBS = 100; // >= 30 min

    IUniswapV3Factory public immutable factory;
    mapping(address => mapping(address => IUniswapV3Pool)) poolsIndex;
    EnumerableSet.AddressSet private _pools;

    constructor(
        IUniswapV3Factory factory_,
        IUniswapV3Pool[] memory pools,
        address admin
    ) DefaultAccessControl(admin) {
        factory = factory_;
        _addUniV3Pools(pools);
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IOracle
    function price(
        address token0,
        address token1,
        uint256 safetyIndicesSet
    ) external view returns (uint256[] memory pricesX96, uint256[] memory actualSafetyIndices) {
        IUniswapV3Pool pool = poolsIndex[token0][token1];
        if (address(pool) == address(0)) {
            return (pricesX96, actualSafetyIndices);
        }
        pricesX96 = new uint256[](4);
        actualSafetyIndices = new uint256[](4);
        uint256 len = 0;
        (uint256 spotSqrtPriceX96, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(
            pool
        ).slot0();
        if (safetyIndicesSet & 0x2 == 1) {
            pricesX96[len] = spotSqrtPriceX96;
            actualSafetyIndices[len] = 1;
        }
        for (uint256 i = 2; i < 5; i++) {
            if (safetyIndicesSet & (1 << i) == 1) {
                uint16 bfAvg = _obsForSafety(i);
                if (observationCardinality > bfAvg) {
                    continue;
                }
                uint256 obs1 = (uint256(observationIndex) + uint256(observationCardinality) - 1) %
                    uint256(observationCardinality);
                uint256 obs0 = (uint256(observationIndex) + uint256(observationCardinality) - bfAvg) %
                    uint256(observationCardinality);
                (uint32 timestamp0, int56 tick0, , ) = IUniswapV3Pool(pool).observations(obs0);
                (uint32 timestamp1, int56 tick1, , ) = IUniswapV3Pool(pool).observations(obs1);
                uint256 timespan = timestamp1 - timestamp0;
                int256 tickAverage = (int256(tick1) - int256(tick0)) / int256(uint256(timespan));
                pricesX96[len] = TickMath.getSqrtRatioAtTick(int24(tickAverage));
                actualSafetyIndices[len] = i;
            }
        }
        bool revTokens = token1 > token0;
        for (uint256 i = 0; i < len; i++) {
            pricesX96[i] = FullMath.mulDiv(pricesX96[i], pricesX96[i], CommonLibrary.Q96);
            if (revTokens) {
                pricesX96[i] = FullMath.mulDiv(1, CommonLibrary.Q96, pricesX96[i]);
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IUniV3Oracle).interfaceId == interfaceId;
    }

    // -------------------------  EXTERNAL, MUTATING  ------------------------------

    function addUniV3Pools(IUniswapV3Pool[] memory pools) external {
        _addUniV3Pools(pools);
    }

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _obsForSafety(uint256 safety) internal pure returns (uint16) {
        if (safety == 2) {
            return LOW_OBS;
        } else if (safety == 3) {
            return MID_OBS;
        } else if (safety == 4) {
            return HIGH_OBS;
        }
        return 0;
    }

    function _addUniV3Pools(IUniswapV3Pool[] memory pools) internal {
        IUniswapV3Pool[] memory replaced = new IUniswapV3Pool[](pools.length);
        uint256 j;
        for (uint256 i = 0; i < pools.length; i++) {
            IUniswapV3Pool pool = pools[i];
            address token0 = pool.token0();
            address token1 = pool.token1();
            _pools.add(address(pool));
            IUniswapV3Pool currentPool = poolsIndex[token0][token1];
            if (address(currentPool) != address(0)) {
                replaced[j] = currentPool;
                j += 1;
            }
            poolsIndex[token0][token1] = pool;
            poolsIndex[token1][token0] = pool;
        }
        assembly {
            mstore(replaced, j)
        }
        emit PoolsAdded(tx.origin, msg.sender, pools, replaced);
    }

    // --------------------------  EVENTS  --------------------------

    event PoolsAdded(
        address indexed origin,
        address indexed sender,
        IUniswapV3Pool[] pools,
        IUniswapV3Pool[] replacedPools
    );
}
