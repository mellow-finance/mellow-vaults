// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface IVaultNft {
    function vault() external view returns (address[] memory);

    function nft() external view returns (uint256);
}
