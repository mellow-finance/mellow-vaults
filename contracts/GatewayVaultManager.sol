// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IGatewayVaultManager.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./VaultManager.sol";

contract GatewayVaultManager is IGatewayVaultManager, VaultManager {
    mapping(uint256 => uint256) private _vaultOwners;

    /// @notice Creates a new contract
    /// @param name Name of the ERC-721 token
    /// @param symbol Symbol of the ERC-721 token
    /// @param factory Vault Factory reference
    /// @param governanceFactory VaultGovernanceOld Factory reference
    /// @param permissionless Anyone can create a new vault
    /// @param governance Refernce to the Governance of the protocol
    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory governanceFactory,
        bool permissionless,
        IProtocolGovernance governance
    ) VaultManager(name, symbol, factory, governanceFactory, permissionless, governance) {}

    function vaultOwnerNft(uint256 nft) public view override returns (uint256) {
        return _vaultOwners[nft];
    }

    function vaultOwner(uint256 nft) external view override returns (address) {
        return vaultForNft(vaultOwnerNft(nft));
    }
}
