// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./UniV3Vault.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Helper contract for UniV3VaultGovernance that can create new UniV3 Vaults.
contract UniV3VaultFactory is IVaultFactory {
    IVaultGovernance public immutable vaultGovernance;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance of this VaultKind
    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @notice Deploy a new vault.
    /// @param vaultTokens ERC20 tokens under vault management
    /// @param options Should equal UniV3 pool fee
    function deployVault(
        address[] memory vaultTokens,
        uint256 nft,
        bytes memory options
    ) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), ExceptionsLibrary.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
        require(options.length == 0 || options.length == 32, ExceptionsLibrary.INVALID_OPTIONS);
        uint256 fee = 3000;
        if (options.length == 32) {
            fee = abi.decode(options, (uint256));
        }
        address addr;
        bytes memory bytecode = type(UniV3Vault).creationCode;
        bytes memory initCode = abi.encodePacked(bytecode, abi.encode(vaultGovernance, vaultTokens, nft, fee));
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), nft)

            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return IVault(addr);
    }
}
