// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./AaveVault.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Helper contract for AaveVaultGovernance that can create new Aave Vaults.
contract AaveVaultFactory is IVaultFactory {
    IVaultGovernance public immutable vaultGovernance;

    /// @notice Creates a new contract
    /// @param vaultGovernance_ Reference to VaultGovernance of this VaultKind
    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @inheritdoc IVaultFactory
    function deployVault(
        address[] memory vaultTokens,
        uint256 nft,
        bytes memory
    ) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), ExceptionsLibrary.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
        address addr;
        bytes memory bytecode = type(AaveVault).creationCode;

        bytes memory initCode = abi.encodePacked(bytecode, abi.encode(vaultGovernance, vaultTokens, nft));
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), nft)

            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return IVault(addr);
    }
}
