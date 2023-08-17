// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/vaults/IERC20Vault.sol";

import "../utils/ContractMeta.sol";

contract SingleVaultStrategy is ContractMeta, ILpCallback {
    IERC20Vault public immutable erc20Vault;
    address public immutable subvault;

    constructor(IERC20Vault erc20Vault_, address subvault_) {
        erc20Vault = erc20Vault_;
        subvault = subvault_;
    }

    /// @inheritdoc ILpCallback
    function depositCallback() external {
        (uint256[] memory tokenAmounts, ) = erc20Vault.tvl();
        if (tokenAmounts[0] > 0 || tokenAmounts[1] > 0) {
            erc20Vault.pull(subvault, erc20Vault.vaultTokens(), tokenAmounts, "");
        }
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback() external {}

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("SingleVaultStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
