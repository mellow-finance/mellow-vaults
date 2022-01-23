// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/external/chainlink/IAggregatorV3.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/DefaultAccessControl.sol";

/// @notice Contract for getting chainlink data
contract ChainlinkOracle is IChainlinkOracle, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _tokenAllowlist;
    mapping(address => address) public chainlinkOracles;

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
    function spotPrice(address token0, address token1) external view returns (uint256 priceX96) {
        require(_tokenAllowlist.contains(token0) && _tokenAllowlist.contains(token1), ExceptionsLibrary.ALLOWLIST);
        require(token1 > token0, ExceptionsLibrary.INVARIANT);
        IAggregatorV3 chainlinkOracle0 = IAggregatorV3(chainlinkOracles[token0]);
        IAggregatorV3 chainlinkOracle1 = IAggregatorV3(chainlinkOracles[token1]);
        require(
            (address(chainlinkOracle0) != address(0)) && (address(chainlinkOracle1) != address(0)),
            ExceptionsLibrary.NOT_FOUND
        );
        priceX96 = _getChainlinkPrice(chainlinkOracle0, chainlinkOracle1);
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

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _getChainlinkPrice(IAggregatorV3 chainlinkOracle0, IAggregatorV3 chainlinkOracle1)
        internal
        view
        returns (uint256)
    {
        (, int256 answer0, , , ) = chainlinkOracle0.latestRoundData(); // this can throw if there's no data
        uint256 decimalsFactor0 = 10**chainlinkOracle0.decimals();
        (, int256 answer1, , , ) = chainlinkOracle1.latestRoundData();
        uint256 decimalsFactor1 = 10**chainlinkOracle0.decimals();
        uint256 decimalsRatioX96 = FullMath.mulDiv(decimalsFactor1, CommonLibrary.Q96, decimalsFactor0);
        return FullMath.mulDiv(uint256(answer0), decimalsRatioX96, uint256(answer1));
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
