// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/vaults/IKyberVaultGovernance.sol";
import "../interfaces/vaults/IKyberVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Kyber Vaults params and can deploy a new Kyber Vault.
contract KyberVaultGovernance is ContractMeta, IKyberVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        require(address(delayedProtocolParams_.positionManager) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(delayedProtocolParams_.farm) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(delayedProtocolParams_.mellowOracle) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IKyberVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IKyberVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return
                DelayedProtocolParams({
                    positionManager: IBasePositionManager(address(0)),
                    farm: IKyberSwapElasticLM(address(0)),
                    mellowOracle: IOracle(address(0))
                });
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IKyberVaultGovernance
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        if (_stagedDelayedStrategyParams[nft].length == 0) {
            bytes[] memory paths = new bytes[](0);
            return DelayedStrategyParams({paths: paths, pid: type(uint256).max});
        }
        return abi.decode(_stagedDelayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IKyberVaultGovernance
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        if (_delayedStrategyParams[nft].length == 0) {
            bytes[] memory paths = new bytes[](0);
            return DelayedStrategyParams({paths: paths, pid: type(uint256).max});
        }
        return abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IKyberVaultGovernance).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IKyberVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        require(address(params.positionManager) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IKyberVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IKyberVaultGovernance
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external {
        _stageDelayedStrategyParams(nft, abi.encode(params));
        emit StageDelayedStrategyParams(tx.origin, msg.sender, nft, params, _delayedStrategyParamsTimestamp[nft]);
    }

    /// @inheritdoc IKyberVaultGovernance
    function commitDelayedStrategyParams(uint256 nft) external {
        _commitDelayedStrategyParams(nft);
        emit CommitDelayedStrategyParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams))
        );
    }

    /// @inheritdoc IKyberVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        uint24 fee_,
        address kyberHelper_
    ) external returns (IKyberVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IKyberVault(vaddr);
        vault.initialize(nft, vaultTokens_, fee_, kyberHelper_);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, abi.encode(fee_), owner_, vaddr, nft);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("KyberVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.1.0");
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new DelayedProtocolParams are staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedProtocolParams(
        address indexed origin,
        address indexed sender,
        DelayedProtocolParams params,
        uint256 when
    );
    /// @notice Emitted when new DelayedProtocolParams are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params New params that are committed
    event CommitDelayedProtocolParams(address indexed origin, address indexed sender, DelayedProtocolParams params);

    /// @notice Emitted when new DelayedStrategyParams are staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedStrategyParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedStrategyParams params,
        uint256 when
    );

    /// @notice Emitted when new DelayedStrategyParams are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that are committed
    event CommitDelayedStrategyParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedStrategyParams params
    );
}
