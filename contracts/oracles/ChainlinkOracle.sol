// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../interfaces/external/chainlink/IAggregatorV3.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/DefaultAccessControl.sol";

/// @notice Contract for getting chainlink data
contract ChainlinkOracle is IContractMeta, IChainlinkOracle, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant CONTRACT_NAME = "ChainlinkOracle";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    mapping(address => address) public chainlinkOracles;

    EnumerableSet.AddressSet private _tokenAllowlist;

    constructor(
        address[] memory tokens,
        address[] memory oracles,
        address admin
    ) DefaultAccessControl(admin) {
        _addChainlinkOracles(tokens, oracles);
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IChainlinkOracle
    function isAllowedToken(address token) external view returns (bool) {
        return _tokenAllowlist.contains(token);
    }

    /// @inheritdoc IChainlinkOracle
    function tokenAllowlist() external view returns (address[] memory) {
        return _tokenAllowlist.values();
    }

    /// @inheritdoc IChainlinkOracle
    function canTellSpotPrice(address token0, address token1) external view returns (bool) {
        return
            _tokenAllowlist.contains(token0) &&
            _tokenAllowlist.contains(token1) &&
            (chainlinkOracles[token0] != address(0)) &&
            (chainlinkOracles[token1] != address(0));
    }

    /// @inheritdoc IExactOracle
    function canTellExactPrice(address token) external view returns (bool) {
        return _tokenAllowlist.contains(token) && (chainlinkOracles[token] != address(0));
    }

    /// @inheritdoc IExactOracle
    function exactPriceX96(address token) external view returns (uint256) {
        require(_tokenAllowlist.contains(token), ExceptionsLibrary.ALLOWLIST);
        IAggregatorV3 chainlinkOracle = IAggregatorV3(chainlinkOracles[token]);
        require(address(chainlinkOracle) != address(0), ExceptionsLibrary.NOT_FOUND);
        (, int256 answer, , , ) = chainlinkOracle.latestRoundData();
        uint256 price = uint256(answer);
        uint256 decimalsFactor = (chainlinkOracle.decimals() + IERC20Metadata(token).decimals());
        return FullMath.mulDiv(price, CommonLibrary.Q96, 10**decimalsFactor);
    }

    /// @inheritdoc IChainlinkOracle
    function spotPriceX96(address token0, address token1) external view returns (uint256 priceX96) {
        require(_tokenAllowlist.contains(token0) && _tokenAllowlist.contains(token1), ExceptionsLibrary.ALLOWLIST);
        require(token1 > token0, ExceptionsLibrary.INVARIANT);
        IAggregatorV3 chainlinkOracle0 = IAggregatorV3(chainlinkOracles[token0]);
        IAggregatorV3 chainlinkOracle1 = IAggregatorV3(chainlinkOracles[token1]);
        require(
            (address(chainlinkOracle0) != address(0)) && (address(chainlinkOracle1) != address(0)),
            ExceptionsLibrary.NOT_FOUND
        );
        (, int256 answer0, , , ) = chainlinkOracle0.latestRoundData(); // this can throw if there's no data
        uint256 decimalsFactor0 = (chainlinkOracle0.decimals() + IERC20Metadata(token0).decimals());
        (, int256 answer1, , , ) = chainlinkOracle1.latestRoundData();
        uint256 decimalsFactor1 = (chainlinkOracle1.decimals() + IERC20Metadata(token1).decimals());
        uint256 price0 = uint256(answer0);
        uint256 price1 = uint256(answer1);
        if (decimalsFactor1 > decimalsFactor0) {
            uint256 decimalsDiff = decimalsFactor1 - decimalsFactor0;
            price0 *= (10**decimalsDiff);
        } else if (decimalsFactor0 > decimalsFactor1) {
            uint256 decimalsDiff = decimalsFactor0 - decimalsFactor1;
            price1 *= (10**decimalsDiff);
        }
        priceX96 = FullMath.mulDiv(price0, CommonLibrary.Q96, price1);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IChainlinkOracle).interfaceId;
    }

    // -------------------------  EXTERNAL, MUTATING  ------------------------------

    /// @inheritdoc IChainlinkOracle
    function addChainlinkOracles(address[] memory tokens, address[] memory oracles) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
        _addChainlinkOracles(tokens, oracles);
    }

    // -------------------------  INTERNAL, MUTATING  ------------------------------

    function _addChainlinkOracles(address[] memory tokens, address[] memory oracles) internal {
        require(tokens.length == oracles.length, ExceptionsLibrary.INVALID_VALUE);
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            address oracle = oracles[i];
            require(!_tokenAllowlist.contains(token), ExceptionsLibrary.DUPLICATE);
            _tokenAllowlist.add(token);
            chainlinkOracles[token] = oracle;
        }
        emit OraclesAdded(tx.origin, msg.sender, tokens, oracles);
    }

    // --------------------------  EVENTS  --------------------------

    event OraclesAdded(address indexed origin, address indexed sender, address[] tokens, address[] oracles);
}
