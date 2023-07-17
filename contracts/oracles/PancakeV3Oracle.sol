// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/external/pancakeswap/IPancakeV3Pool.sol";
import "../interfaces/external/pancakeswap/IPancakeV3Factory.sol";
import "../interfaces/external/pancakeswap/libraries/OracleLibrary.sol";

import "../interfaces/oracles/IPancakeV3Oracle.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";

import "../utils/DefaultAccessControl.sol";
import "../utils/ContractMeta.sol";

contract PancakeV3Oracle is ContractMeta, IPancakeV3Oracle, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IPancakeV3Oracle
    uint32 public constant LOW_OBS_DELTA = 150; // 2.5 min
    /// @inheritdoc IPancakeV3Oracle
    uint32 public constant MID_OBS_DELTA = 450; // 7.5 min
    /// @inheritdoc IPancakeV3Oracle
    uint32 public constant HIGH_OBS_DELTA = 1800; // 30 min

    /// @inheritdoc IPancakeV3Oracle
    IPancakeV3Factory public immutable factory;
    /// @inheritdoc IPancakeV3Oracle
    mapping(address => mapping(address => IPancakeV3Pool)) public poolsIndex;
    EnumerableSet.AddressSet private _pools;

    constructor(
        IPancakeV3Factory factory_,
        IPancakeV3Pool[] memory pools,
        address admin
    ) DefaultAccessControl(admin) {
        factory = factory_;
        _addPancakeV3Pools(pools);
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @dev Logic of this function is next:
    /// If there is no initialized pool for the passed tokens, empty arrays will be returned.
    /// Depending on safetyIndicesSet if the 1st bit in safetyIndicesSet is non-zero, then the response will contain the spot price.
    /// If there is a non-zero 2nd bit in the safetyIndicesSet and the corresponding position in the pool was created no later than LOW_OBS_DELTA seconds ago,
    /// then the average price for the last LOW_OBS_DELTA seconds will be returned. The same logic exists for the 3rd and MID_OBS_DELTA, and 4th index and HIGH_OBS_DELTA.
    /// @inheritdoc IOracle
    function priceX96(
        address token0,
        address token1,
        uint256 safetyIndicesSet
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        bool isSwapped = false;
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            isSwapped = true;
        }
        IPancakeV3Pool pool = poolsIndex[token0][token1];
        if (address(pool) == address(0)) {
            return (pricesX96, safetyIndices);
        }
        uint256[] memory sqrtPricesX96 = new uint256[](4);
        pricesX96 = new uint256[](4);
        safetyIndices = new uint256[](4);
        uint256 len = 0;
        if (safetyIndicesSet & 0x2 > 0) {
            (uint256 spotSqrtPriceX96, , , , , , ) = IPancakeV3Pool(pool).slot0();
            sqrtPricesX96[len] = spotSqrtPriceX96;
            safetyIndices[len] = 1;
            len += 1;
        }
        for (uint256 i = 2; i < 5; i++) {
            if (safetyIndicesSet & (1 << i) > 0) {
                uint32 observationTimeDelta = _obsTimeForSafety(i);
                (int24 tickAverage, , bool withFail) = OracleLibrary.consult(address(pool), observationTimeDelta);
                if (withFail) {
                    break;
                }
                sqrtPricesX96[len] = TickMath.getSqrtRatioAtTick(tickAverage);
                safetyIndices[len] = i;
                len += 1;
            }
        }
        assembly {
            mstore(pricesX96, len)
            mstore(safetyIndices, len)
        }
        for (uint256 i = 0; i < len; i++) {
            pricesX96[i] = FullMath.mulDiv(sqrtPricesX96[i], sqrtPricesX96[i], CommonLibrary.Q96);
            if (isSwapped) {
                pricesX96[i] = FullMath.mulDiv(CommonLibrary.Q96, CommonLibrary.Q96, pricesX96[i]);
            }
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IPancakeV3Oracle).interfaceId == interfaceId;
    }

    // -------------------------  EXTERNAL, MUTATING  ------------------------------

    /// @inheritdoc IPancakeV3Oracle
    function addPancakeV3Pools(IPancakeV3Pool[] memory pools) external {
        _requireAdmin();
        _addPancakeV3Pools(pools);
    }

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("PancakeV3Oracle");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _obsTimeForSafety(uint256 safety) internal pure returns (uint32) {
        if (safety == 2) {
            return LOW_OBS_DELTA;
        } else if (safety == 3) {
            return MID_OBS_DELTA;
        } else {
            require(safety == 4, ExceptionsLibrary.INVALID_VALUE);
            return HIGH_OBS_DELTA;
        }
    }

    function _addPancakeV3Pools(IPancakeV3Pool[] memory pools) internal {
        IPancakeV3Pool[] memory replaced = new IPancakeV3Pool[](pools.length);
        IPancakeV3Pool[] memory added = new IPancakeV3Pool[](pools.length);
        uint256 j;
        uint256 k;
        for (uint256 i = 0; i < pools.length; i++) {
            IPancakeV3Pool pool = pools[i];
            address token0 = pool.token0();
            address token1 = pool.token1();
            _pools.add(address(pool));
            IPancakeV3Pool currentPool = poolsIndex[token0][token1];
            if (address(currentPool) != address(0)) {
                replaced[j] = currentPool;
                j += 1;
            } else {
                added[k] = pool;
                k += 1;
            }
            poolsIndex[token0][token1] = pool;
        }
        assembly {
            mstore(replaced, j)
            mstore(added, k)
        }
        emit PoolsUpdated(tx.origin, msg.sender, added, replaced);
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new pool is added or updated and become available for oracle prices
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param pools PancakeV3 pools added
    /// @param replacedPools PancakeV3 pools updated
    event PoolsUpdated(
        address indexed origin,
        address indexed sender,
        IPancakeV3Pool[] pools,
        IPancakeV3Pool[] replacedPools
    );
}
