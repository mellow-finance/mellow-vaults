// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultFactory.sol";

interface IERC20RootVaultFactory is IVaultFactory {
    function getDeploymentAddress(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        uint256 nft_,
        address strategy,
        uint256[] memory subvaultNfts_,
        string memory name_,
        string memory symbol_
    ) external view returns (address);
}
