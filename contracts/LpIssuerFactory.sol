// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./LpIssuer.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Helper contract for LpIssuerGovernance that can create new LpIssuers.
contract LpIssuerFactory is IVaultFactory {
    IVaultGovernance public immutable vaultGovernance;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance of this VaultKind
    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @inheritdoc IVaultFactory
    function deployVault(
        address[] memory vaultTokens,
        uint256 nft,
        bytes memory options
    ) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), ExceptionsLibrary.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
        address addr;
        (string memory name, string memory symbol) = abi.decode(options, (string, string));
        bytes memory bytecode = type(LpIssuer).creationCode;
        bytes memory initCode = abi.encodePacked(bytecode, abi.encode(vaultGovernance, vaultTokens, nft, name, symbol));
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), nft)

            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return IVault(addr);
    }
}
