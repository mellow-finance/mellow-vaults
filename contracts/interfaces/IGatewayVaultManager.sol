// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";

interface IGatewayVaultManager {
    function vaultOwnerNft(uint256 nft) external view returns (uint256);

    function vaultOwner(uint256 nft) external view returns (address);
}
