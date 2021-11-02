// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./libraries/Common.sol";

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/ILpIssuerVaultGovernance.sol";
import "./VaultGovernance.sol";

contract LpIssuerGovernance is ILpIssuerVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    function deployVault(
        address[] memory vaultTokens,
        bytes memory options,
        address strategy
    ) public override(VaultGovernance, IVaultGovernance) returns (IVault vault, uint256 nft) {
        (vault, nft) = super.deployVault(vaultTokens, "", msg.sender);
        uint256[] memory subvaultNfts = abi.decode(options, (uint256[]));
        IVaultRegistry registry = _internalParams.registry;
        IGatewayVault(address(vault)).addSubvaults(subvaultNfts);
        for (uint256 i = 0; i < subvaultNfts.length; i++) {
            registry.transferFrom(msg.sender, address(this), subvaultNfts[i]);
            registry.approve(strategy, subvaultNfts[i]);
        }
    }
}
