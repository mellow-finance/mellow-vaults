// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVaultGovernance.sol";
import "../interfaces/IVaultFactory.sol";
import "../GatewayVault.sol";

contract GatewayVaultTest is GatewayVault {
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        GatewayVault(vaultGovernance_, vaultTokens_)
    {}

    function isValidEdge(address from, address to) public view returns (bool) {
        return _isValidEdge(from, to);
    }

    function setVaultGovernance(address newVaultGovernance) public {
        _vaultGovernance = IVaultGovernance(newVaultGovernance);
    }

    function setSubvaultNfts(uint256[] memory nfts) public {
        _subvaultNfts = nfts;
    }

    function collectFees(uint256[] memory collectedEarnings) internal returns (uint256[] memory collectedFees) {
        _collectFees(collectedEarnings);
    }
}
