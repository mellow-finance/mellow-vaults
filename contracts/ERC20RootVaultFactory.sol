// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./interfaces/IERC20RootVaultFactory.sol";
import "./ERC20RootVault.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Helper contract for ERC20RootVaultGovernance that can create new ERC20RootVaults.
contract ERC20RootVaultFactory is IERC20RootVaultFactory {
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
        (address strategy, uint256[] memory subvaultTokens, string memory name, string memory symbol) = abi.decode(
            options,
            (address, uint256[], string, string)
        );
        bytes memory bytecode = type(ERC20RootVault).creationCode;
        bytes memory initCode = abi.encodePacked(
            bytecode,
            abi.encode(vaultGovernance, vaultTokens, nft, strategy, subvaultTokens, name, symbol)
        );
        assembly {
            addr := create2(0, add(initCode, 0x20), mload(initCode), nft)

            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return IVault(addr);
    }

    function getDeploymentAddress(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        uint256 nft_,
        address strategy,
        uint256[] memory subvaultNfts_,
        string memory name_,
        string memory symbol_
    ) external view returns (address) {
        bytes memory creatonCode = type(ERC20RootVault).creationCode;
        bytes memory bytecode = abi.encodePacked(
            creatonCode,
            abi.encode(vaultGovernance_, vaultTokens_, nft_, strategy, subvaultNfts_, name_, symbol_)
        );
        bytes32 addressHash = keccak256(abi.encodePacked(bytes1(0xff), address(this), nft_, keccak256(bytecode)));
        return address(uint160(uint256(addressHash)));
    }
}
