// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IGatewayVaultManager.sol";
import "./interfaces/IGatewayVaultGovernance.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./VaultGovernanceOld.sol";

contract GatewayVaultGovernance is IGatewayVaultGovernance, VaultGovernanceOld {
    address[] private _redirects;
    uint256[] private _limits;

    /// @notice Creates a new contract
    /// @param tokens A set of tokens that will be managed by the Vault
    /// @param manager Reference to Gateway Vault Manager
    /// @param treasury Strategy treasury address that will be used to collect Strategy Performance Fee
    /// @param admin Admin of the Vault
    /// @param redirects_ Subvaults of the vault
    constructor(
        address[] memory tokens,
        IVaultManager manager,
        address treasury,
        address admin,
        address[] memory redirects_,
        uint256[] memory limits_
    ) VaultGovernanceOld(tokens, manager, treasury, admin) {
        _redirects = redirects_;
        _limits = limits_;
    }

    function limits() external view returns (uint256[] memory) {
        return _limits;
    }

    function redirects() external view returns (address[] memory) {
        return _redirects;
    }

    function setLimits(uint256[] calldata newLimits) external {
        require(isAdmin(msg.sender), "ADM");
        require(newLimits.length == vaultTokens().length, "TL");
        _limits = newLimits;
        emit SetLimits(newLimits);
    }

    function setRedirects(address[] calldata newRedirects) external {
        require(isAdmin(msg.sender), "ADM");
        require(newRedirects.length == vaultTokens().length, "TL");
        _redirects = newRedirects;
        emit SetRedirects(newRedirects);
    }

    event SetLimits(uint256[] limits);
    event SetRedirects(address[] redirects);
}
