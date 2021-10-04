// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";

interface IVaultsGovernance is IERC721 {
    struct VaultParams {
        uint256 fee;
        uint256 feeReceiver;
    }

    struct VaultsParams {
        bool permissionless;
        IProtocolGovernance protocolGovernance;
    }

    function pendingVaultParamsTimestamp(uint256 nft) external view returns (uint256);

    function pendingVaultParams(uint256 nft) external view returns (VaultParams memory);

    function vaultParams(uint256 nft) external view returns (VaultParams memory);

    function setPendingVaultParams(uint256 nft, VaultParams memory newParams) external;

    function commitVaultParams(uint256 nft) external;

    function pendingVaultsParamsTimestamp() external view returns (uint256);

    function pendingVaultsParams() external view returns (VaultsParams memory);

    function vaultsParams() external view returns (VaultsParams memory);

    function setPendingVaultsParams(VaultsParams memory newParams) external;

    function commitVaultsParams() external;

    function pendingVaultLimitsTimestamp(uint256 nft) external view returns (uint256);

    function pendingVaultLimits(uint256 nft) external view returns (uint256[] memory);

    function vaultLimits(uint256 nft) external view returns (uint256[] memory);

    function setPendingVaultLimits(uint256 nft, uint256[] memory newVaultLimits) external;

    function commitVaultLimits(uint256 nft) external;

    event SetPendingVaultLimits(uint256 indexed nft, uint256 timestamp, uint256[] newVaultLimits);
    event CommitVaultLimits(uint256 indexed nft, uint256[] newVaultLimits);
    event SetPendingVaultParams(uint256 indexed nft, uint256 timestamp, VaultParams newVaultParams);
    event CommitVaultParams(uint256 indexed nft, VaultParams newVaultParams);
    event SetPendingVaultsParams(uint256 timestamp, VaultsParams newVaultsParams);
    event CommitVaultsParams(VaultsParams newVaultsParams);
}
