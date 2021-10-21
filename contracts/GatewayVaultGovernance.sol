// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IGatewayVaultManager.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./VaultGovernance.sol";

contract GatewayVaultGovernance is VaultGovernance {
    address[] private _redirects;
    address[] private _vaults;
    uint256[] private _limits;

    constructor(
        address[] memory tokens,
        IVaultManager manager,
        address treasury,
        address admin,
        address[] memory vaults,
        address[] memory redirects_,
        uint256[] memory limits_
    ) VaultGovernance(tokens, manager, treasury, admin) {
        _redirects = redirects_;
        _limits = limits_;
        _vaults = vaults;
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
