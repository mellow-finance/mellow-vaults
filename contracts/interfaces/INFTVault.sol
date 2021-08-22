// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./ITokensEntity.sol";

interface INftVault is IERC165, IERC721, IERC721Receiver {
    struct VaultNft {
        uint256 nft;
        address vault;
    }

    function ownedNfts(uint256 nft) external view returns (VaultNft[] memory);

    function tokens(uint256 nft) external view returns (IERC20[] memory);

    function tokenAmounts(uint256 nft) external view returns (uint256[] memory);

    function owedTokenAmounts(uint256 nft) external view returns (uint256[] memory);

    function totalTokenAmounts(uint256 nft) external view returns (uint256[] memory);

    function deposit(uint256 nft, uint256[] calldata caps) external;

    function withdraw(uint256 nft, uint256[] calldata caps) external;
}
