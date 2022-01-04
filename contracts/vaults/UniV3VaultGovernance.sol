// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IUniV3VaultGovernance.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all UniV3 Vaults params and can deploy a new UniV3 Vault.
contract UniV3VaultGovernance is IUniV3VaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        require(address(delayedProtocolParams_.positionManager) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    /// @inheritdoc IUniV3VaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        if (_delayedProtocolParams.length == 0) {
            return
                DelayedProtocolParams({
                    positionManager: INonfungiblePositionManager(address(0)),
                    oracle: IMellowOracle(address(0))
                });
        }
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IUniV3VaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return
                DelayedProtocolParams({
                    positionManager: INonfungiblePositionManager(address(0)),
                    oracle: IMellowOracle(address(0))
                });
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IUniV3VaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IUniV3VaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IUniV3VaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        uint24 fee_,
        address owner_
    ) external returns (IUniV3Vault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IUniV3Vault(vaddr);
        vault.initialize(nft, vaultTokens_, fee_);
    }

    /// @notice Emitted when new DelayedProtocolParams are staged for commit
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedProtocolParams(
        address indexed origin,
        address indexed sender,
        DelayedProtocolParams params,
        uint256 when
    );
    /// @notice Emitted when new DelayedProtocolParams are committed
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param params New params that are committed
    event CommitDelayedProtocolParams(address indexed origin, address indexed sender, DelayedProtocolParams params);
}
