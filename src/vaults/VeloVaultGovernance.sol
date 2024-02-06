// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/IVeloVault.sol";
import "../interfaces/vaults/IVeloVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Velodrome Vaults params and can deploy a new VeloVault.
contract VeloVaultGovernance is ContractMeta, IVeloVaultGovernance, VaultGovernance {
    /// @notice The maximum protocol fee that can be charged, represented as a scaled integer.
    /// The value is set to 3e8, which corresponds to a 30% fee.
    uint256 public constant MAX_PROTOCOL_FEE = 3e8; // 30%

    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IVeloVaultGovernance).interfaceId == interfaceId;
    }

    /// @inheritdoc IVeloVaultGovernance
    function strategyParams(uint256 nft) external view returns (StrategyParams memory) {
        if (_strategyParams[nft].length == 0) {
            return
                StrategyParams({
                    gauge: address(0),
                    farmingPool: address(0),
                    protocolFeeD9: 0,
                    protocolTreasury: address(0)
                });
        }
        return abi.decode(_strategyParams[nft], (StrategyParams));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IVeloVaultGovernance
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external {
        require(
            params.farmingPool != address(0) && params.protocolTreasury != address(0) && params.gauge != address(0),
            ExceptionsLibrary.ADDRESS_ZERO
        );
        require(params.protocolFeeD9 <= MAX_PROTOCOL_FEE, ExceptionsLibrary.LIMIT_OVERFLOW);
        _setStrategyParams(nft, abi.encode(params));
        emit SetStrategyParams(tx.origin, msg.sender, nft, params);
    }

    /// @inheritdoc IVeloVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        int24 tickSpacing_
    ) external returns (IVeloVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IVeloVault(vaddr);
        vault.initialize(nft, vaultTokens_, tickSpacing_);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, abi.encode(tickSpacing_), owner_, vaddr, nft);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("VeloVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // --------------------------  EVENTS  --------------------------
    /// @notice Emitted when new StrategyParams are set
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New set params
    event SetStrategyParams(address indexed origin, address indexed sender, uint256 indexed nft, StrategyParams params);
}
