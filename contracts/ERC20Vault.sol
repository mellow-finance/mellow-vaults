// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Vault.sol";

/// @notice Vault that stores ERC20 tokens.
contract ERC20Vault is Vault {
    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {}

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }

    /// @inheritdoc Vault
    function earnings() public view override returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](_vaultTokens.length);
    }

    function _push(
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal pure override returns (uint256[] memory actualTokenAmounts) {
        // no-op, tokens are already on balance
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            IERC20(_vaultTokens[i]).transfer(to, tokenAmounts[i]);
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
        collectedEarnings = new uint256[](_vaultTokens.length);
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(!_isVaultToken(tokens[i]), "OWT"); // vault token is part of TVL
        }
    }
}
