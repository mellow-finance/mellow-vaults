// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";

interface IVaultManager is IERC721 {
    function nftForVault(address vault) external view returns (uint256);

    function protocolGovernance() external view returns (IProtocolGovernance);

    function createVault(address[] memory tokens, uint256[] memory limits) external returns (address, uint256);
}
