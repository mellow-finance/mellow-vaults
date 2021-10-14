// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";
import "./IVaultManagerGovernance.sol";
import "./IVaultGovernance.sol";

interface IVaultManager is IERC721, IVaultManagerGovernance {
    function nftForVault(address vault) external view returns (uint256);

    function vaultForNft(uint256 nft) external view returns (address);

    function createVault(
        address[] calldata tokens,
        address strategyTreasury,
        address admin,
        bytes memory options
    )
        external
        returns (
            IVaultGovernance vaultGovernance,
            IVault vault,
            uint256 nft
        );

    event CreateVault(address vaultGovernance, address vault, uint256 nft, address[] tokens, bytes options);
}
