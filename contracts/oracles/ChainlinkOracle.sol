// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/external/chainlink/IAggregatorV3.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/DefaultAccessControl.sol";
import "../utils/ContractMeta.sol";

/// @notice Contract for getting chainlink data
contract ChainlinkOracle is ContractMeta, IChainlinkOracle, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IChainlinkOracle
    uint8 public constant safetyIndex = 5;
    /// @inheritdoc IChainlinkOracle
    mapping(address => address) public oraclesIndex;
    /// @inheritdoc IChainlinkOracle
    mapping(address => int256) public decimalsIndex;
    EnumerableSet.AddressSet private _tokens;

    constructor(
        address[] memory tokens,
        address[] memory oracles,
        address admin
    ) DefaultAccessControl(admin) {
        _addChainlinkOracles(tokens, oracles);
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IChainlinkOracle
    function hasOracle(address token) external view returns (bool) {
        return _tokens.contains(token);
    }

    /// @inheritdoc IChainlinkOracle
    function supportedTokens() external view returns (address[] memory) {
        return _tokens.values();
    }

    /// @inheritdoc IOracle
    function priceX96(
        address token0,
        address token1,
        uint256 safetyIndicesSet
    ) external view returns (uint256[] memory pricesX96, uint256[] memory safetyIndices) {
        if (((safetyIndicesSet >> safetyIndex) & 1) != 1) {
            return (pricesX96, safetyIndices);
        }
        IAggregatorV3 chainlinkOracle0 = IAggregatorV3(oraclesIndex[token0]);
        IAggregatorV3 chainlinkOracle1 = IAggregatorV3(oraclesIndex[token1]);
        if ((address(chainlinkOracle0) == address(0)) || (address(chainlinkOracle1) == address(0))) {
            return (pricesX96, safetyIndices);
        }
        uint256 price0;
        uint256 price1;
        bool success;
        (success, price0) = _queryChainlinkOracle(chainlinkOracle0);
        if (!success) {
            return (pricesX96, safetyIndices);
        }
        (success, price1) = _queryChainlinkOracle(chainlinkOracle1);
        if (!success) {
            return (pricesX96, safetyIndices);
        }

        int256 decimals0 = decimalsIndex[token0];
        int256 decimals1 = decimalsIndex[token1];
        if (decimals1 > decimals0) {
            price1 *= 10**(uint256(decimals1 - decimals0));
        } else if (decimals0 > decimals1) {
            price0 *= 10**(uint256(decimals0 - decimals1));
        }
        pricesX96 = new uint256[](1);
        safetyIndices = new uint256[](1);
        pricesX96[0] = FullMath.mulDiv(price0, CommonLibrary.Q96, price1);
        safetyIndices[0] = safetyIndex;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IChainlinkOracle).interfaceId;
    }

    // -------------------------  EXTERNAL, MUTATING  ------------------------------

    /// @inheritdoc IChainlinkOracle
    function addChainlinkOracles(address[] memory tokens, address[] memory oracles) external {
        _requireAdmin();
        _addChainlinkOracles(tokens, oracles);
    }

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _queryChainlinkOracle(IAggregatorV3 oracle) internal view returns (bool success, uint256 answer) {
        try oracle.latestRoundData() returns (uint80, int256 ans, uint256, uint256, uint80) {
            return (true, uint256(ans));
        } catch (bytes memory) {
            return (false, 0);
        }
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("ChainlinkOracle");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // -------------------------  INTERNAL, MUTATING  ------------------------------

    function _addChainlinkOracles(address[] memory tokens, address[] memory oracles) internal {
        require(tokens.length == oracles.length, ExceptionsLibrary.INVALID_VALUE);
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            address oracle = oracles[i];
            _tokens.add(token);
            oraclesIndex[token] = oracle;
            decimalsIndex[token] = int256(
                -int8(IERC20Metadata(token).decimals()) - int8(IAggregatorV3(oracle).decimals())
            );
        }
        emit OraclesAdded(tx.origin, msg.sender, tokens, oracles);
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new Chainlink oracle is added
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param tokens Tokens added
    /// @param oracles Orecles added for the tokens
    event OraclesAdded(address indexed origin, address indexed sender, address[] tokens, address[] oracles);
}
