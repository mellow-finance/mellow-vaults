// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../interfaces/IProtocolGovernance.sol";
import "./interfaces/ITrader.sol";
import "./interfaces/IChiefTrader.sol";
import "./libraries/TraderExceptionsLibrary.sol";

/// @notice Main contract that allows trading of ERC20 tokens on different Dexes
/// @dev This contract contains several subtraders that can be used for trading ERC20 tokens.
/// Examples of subtraders are UniswapV3, UniswapV2, SushiSwap, Curve, etc.
contract ChiefTrader is ERC165, IChiefTrader, ITrader {
    IProtocolGovernance public immutable protocolGovernance;
    address[] internal _traders;
    mapping(address => bool) public addedTraders;

    constructor(address _protocolGovernance) {
        protocolGovernance = IProtocolGovernance(_protocolGovernance);
    }

    /// @inheritdoc IChiefTrader
    function tradersCount() external view returns (uint256) {
        return _traders.length;
    }

    /// @inheritdoc IChiefTrader
    function getTrader(uint256 _index) external view returns (address) {
        return _traders[_index];
    }

    /// @inheritdoc IChiefTrader
    function traders() external view returns (address[] memory) {
        return _traders;
    }

    /// @inheritdoc IChiefTrader
    function addTrader(address traderAddress) external {
        _requireProtocolAdmin();
        require(!addedTraders[traderAddress], TraderExceptionsLibrary.TRADER_ALREADY_REGISTERED_EXCEPTION);
        require(ERC165(traderAddress).supportsInterface(type(ITrader).interfaceId));
        require(!ERC165(traderAddress).supportsInterface(type(IChiefTrader).interfaceId));
        _traders.push(traderAddress);
        addedTraders[traderAddress] = true;
        emit AddedTrader(_traders.length - 1, traderAddress);
    }

    /// @inheritdoc ITrader
    function swapExactInput(
        uint256 traderId,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes calldata options
    ) external returns (uint256 amountOut) {
        require(traderId < _traders.length, TraderExceptionsLibrary.TRADER_NOT_FOUND_EXCEPTION);
        _requireAllowedTokens(token0, token1);
        address traderAddress = _traders[traderId];
        amountOut = ITrader(traderAddress).swapExactInput(0, recipient, token0, token1, amount, options);
    }

    /// @inheritdoc ITrader
    function swapExactOutput(
        uint256 traderId,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes calldata options
    ) external returns (uint256 amountIn) {
        require(traderId < _traders.length, TraderExceptionsLibrary.TRADER_NOT_FOUND_EXCEPTION);
        _requireAllowedTokens(token0, token1);
        address traderAddress = _traders[traderId];
        amountIn = ITrader(traderAddress).swapExactOutput(0, recipient, token0, token1, amount, options);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == this.supportsInterface.selector ||
            interfaceId == type(ITrader).interfaceId ||
            interfaceId == type(IChiefTrader).interfaceId);
    }

    function _requireAllowedTokens(address token0, address token1) internal view {
        require(token0 != token1);
        require(
            protocolGovernance.isAllowedToken(token0) &&
            protocolGovernance.isAllowedToken(token1),
            TraderExceptionsLibrary.TOKEN_NOT_ALLOWED_EXCEPTION
        );
    }

    function _requireProtocolAdmin() internal view {
        require(protocolGovernance.isAdmin(msg.sender), TraderExceptionsLibrary.PROTOCOL_ADMIN_REQUIRED_EXCEPTION);
    }

    event AddedTrader(uint256 indexed traderId, address traderAddress);
}
