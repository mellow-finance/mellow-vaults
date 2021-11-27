// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultRegistry.sol";
import "../interfaces/IProtocolGovernance.sol";
import "./interfaces/ITrader.sol";
import "./interfaces/IChiefTrader.sol";
import "./libraries/Exceptions.sol";

contract ChiefTrader is ERC165, IChiefTrader, ITrader {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable protocolGovernance;
    address public immutable vaultRegistry;
    EnumerableSet.AddressSet internal _traders;

    constructor(address _protocolGovernance, address _vaultRegistry) {
        protocolGovernance = _protocolGovernance;
        vaultRegistry = _vaultRegistry;
    }

    function tradersCount() external view returns (uint256) {
        return _traders.length();
    }

    function traders() external view returns (address[] memory) {
        return _traders.values();
    }

    function addTrader(address traderAddress) external {
        _requireProtocolAdmin();
        require(!_traders.contains(traderAddress));
        require(ERC165(traderAddress).supportsInterface(type(ITrader).interfaceId));
        _traders.add(traderAddress);
    }

    function swapExactInput(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        address,
        PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256) {
        _requireVault();
        _requireVaultTokenOutput(output);
        require(traderId < _traders.length(), Exceptions.TRADER_NOT_FOUND_EXCEPTION);
        address traderAddress = _traders.at(traderId);
        address recipient = msg.sender;
        return ITrader(traderAddress).swapExactInput(0, input, output, amount, recipient, path, options);
    }

    function swapExactOutput(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        address,
        PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256) {
        _requireVault();
        _requireVaultTokenOutput(output);
        require(traderId < _traders.length(), Exceptions.TRADER_NOT_FOUND_EXCEPTION);
        address traderAddress = _traders.at(traderId);
        address recipient = msg.sender;
        return ITrader(traderAddress).swapExactOutput(0, input, output, amount, recipient, path, options);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == this.supportsInterface.selector ||
            interfaceId == type(ITrader).interfaceId ||
            interfaceId == type(IChiefTrader).interfaceId);
    }

    function _requireProtocolAdmin() internal view {
        require(
            IProtocolGovernance(protocolGovernance).isAdmin(msg.sender),
            Exceptions.PROTOCOL_ADMIN_REQUIRED_EXCEPTION
        );
    }

    function _requireVault() internal view {
        require(IVaultRegistry(vaultRegistry).nftForVault(msg.sender) != 0, Exceptions.VAULT_NOT_FOUND_EXCEPTION);
    }

    function _requireVaultTokenOutput(address tokenOutputAddress) internal view {
        require(IVault(msg.sender).isVaultToken(tokenOutputAddress), Exceptions.VAULT_TOKEN_REQUIRED_EXCEPTION);
    }

    function _requireAtLeastStrategy(uint256 nft_) internal view {
        require(
            IProtocolGovernance(protocolGovernance).isAdmin(msg.sender) ||
                (IVaultRegistry(vaultRegistry).getApproved(nft_) == msg.sender ||
                    IVaultRegistry(vaultRegistry).ownerOf(nft_) == msg.sender),
            Exceptions.AT_LEAST_STRATEGY_REQUIRED_EXCEPTION
        );
    }
}
