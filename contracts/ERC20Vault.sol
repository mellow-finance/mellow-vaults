// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Vault.sol";

contract ERC20Vault is Vault {
    /// @notice Creates a new contract
    /// @param vaultGovernance Reference to VaultGovernanceOld for this vault
    constructor(IVaultGovernanceOld vaultGovernance) Vault(vaultGovernance) {}

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultGovernance.vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }

    /// @inheritdoc Vault
    function earnings() public view override returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](_vaultGovernance.vaultTokens().length);
    }

    function _push(
        uint256[] memory tokenAmounts,
        bool,
        bytes memory
    ) internal pure override returns (uint256[] memory actualTokenAmounts) {
        // no-op, tokens are already on balance
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bool,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            IERC20(_vaultGovernance.vaultTokens()[i]).transfer(to, tokenAmounts[i]);
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _collectEarnings(address, bytes memory)
        internal
        view
        override
        returns (uint256[] memory collectedEarnings)
    {
        // no-op, no earnings here
        collectedEarnings = new uint256[](_vaultGovernance.vaultTokens().length);
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(!_vaultGovernance.isVaultToken(tokens[i]), "OWT"); // vault token is part of TVL
        }
    }
}
