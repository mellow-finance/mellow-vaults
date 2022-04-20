// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/oracles/IChainlinkOracle.sol";
import "../interfaces/oracles/IMellowOracle.sol";
import "../interfaces/oracles/IUniV2Oracle.sol";
import "../interfaces/oracles/IUniV3Oracle.sol";
import "../interfaces/oracles/IOracle.sol";
import "../interfaces/vaults/IVault.sol";
import "../interfaces/IVaultRegistry.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/vaults/IIntegrationVault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IYearnVault.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IERC20RootVault.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract InterfaceMapper {
    bytes4 public ERC165_INTERFACE_ID = type(IERC165).interfaceId;
    bytes4 public CHAINLINK_ORACLE_INTERFACE_ID = type(IChainlinkOracle).interfaceId;
    bytes4 public UNIV2_ORACLE_INTERFACE_ID = type(IUniV2Oracle).interfaceId;
    bytes4 public UNIV3_ORACLE_INTERFACE_ID = type(IUniV3Oracle).interfaceId;
    bytes4 public ORACLE_INTERFACE_ID = type(IOracle).interfaceId;
    bytes4 public MELLOW_ORACLE_INTERFACE_ID = type(IMellowOracle).interfaceId;

    bytes4 public CHIEF_TRADER_INTERFACE_ID = 0x698afc85;
    bytes4 public TRADER_INTERFACE_ID = 0xdf1e4f02;
    bytes4 public ZERO_INTERFACE_ID = 0x00000000;

    bytes4 public VAULT_INTERFACE_ID = type(IVault).interfaceId;
    bytes4 public VAULT_REGISTRY_INTERFACE_ID = type(IVaultRegistry).interfaceId;

    bytes4 public INTEGRATION_VAULT_INTERFACE_ID = type(IIntegrationVault).interfaceId;
    bytes4 public UNIV3_VAULT_INTERFACE_ID = type(IUniV3Vault).interfaceId;
    bytes4 public AAVE_VAULT_INTERFACE_ID = type(IAaveVault).interfaceId;
    bytes4 public YEARN_VAULT_INTERFACE_ID = type(IYearnVault).interfaceId;

    bytes4 public PROTOCOL_GOVERNANCE_INTERFACE_ID = type(IProtocolGovernance).interfaceId;
    bytes4 public VALIDATOR_INTERFACE_ID = type(IValidator).interfaceId;
    bytes4 public ERC20_ROOT_VAULT_GOVERNANCE = type(IERC20RootVaultGovernance).interfaceId;
    bytes4 public ERC20_ROOT_VAULT_INTERFACE_ID = type(IERC20RootVault).interfaceId;
}
