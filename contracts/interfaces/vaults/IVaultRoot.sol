// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IVaultRoot {
    function hasSubvault(uint256 nft_) external view returns (bool);

    function subvaultAt(uint256 index) external view returns (address);

    function subvaultNfts() external view returns (uint256[] memory);
}
