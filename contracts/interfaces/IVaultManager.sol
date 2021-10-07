// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";
import "./IVaultManagerGovernance.sol";

interface IVaultManager is IERC721, IVaultManagerGovernance {
    function nftForVault(address vault) external view returns (uint256);

    function vaultForNft(uint256 nft) external view returns (address);

    function createVault(
        address[] calldata tokens,
        uint256[] calldata limits,
        bytes calldata options
    ) external;

    event CreateVault(address vault, uint256 nft, address[] tokens, uint256[] limits);
}
