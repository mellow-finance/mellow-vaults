// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVaultGovernance.sol";
import "../interfaces/IVaultFactory.sol";
import "../GatewayVault.sol";

contract GatewayVaultTest is GatewayVault {
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        GatewayVault(vaultGovernance_, vaultTokens_)
    {}

    function isValidPullDestination(address to) public view returns (bool) {
        return _isValidPullDestination(to);
    }

    function setVaultGovernance(address newVaultGovernance) public {
        _vaultGovernance = IVaultGovernance(newVaultGovernance);
    }

    function setSubvaultNfts(uint256[] memory nfts) public {
        _subvaultNfts = nfts;
    }

    function collectFees(uint256[] memory collectedEarnings) public returns (uint256[] memory collectedFees) {
        _collectFees(collectedEarnings);
    }

    function isApprovedOrOwner(address sender) public view returns (bool) {
        return _isApprovedOrOwner(sender);
    }

    function isVaultToken(address token) public view returns (bool) {
        return _isVaultToken(token);
    }
}
