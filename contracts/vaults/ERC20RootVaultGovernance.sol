// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Lp Issuers params and can deploy a new LpIssuer Vault.
contract ERC20RootVaultGovernance is ContractMeta, IERC20RootVaultGovernance, VaultGovernance {
    bytes32 public constant CONTRACT_NAME = "ERC20RootVaultGovernance";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    uint256 public immutable MAX_PROTOCOL_FEE;
    uint256 public immutable MAX_MANAGEMENT_FEE;
    uint256 public immutable MAX_PERFORMANCE_FEE;

    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
        MAX_PROTOCOL_FEE = (5 * CommonLibrary.DENOMINATOR) / 100;
        MAX_MANAGEMENT_FEE = (10 * CommonLibrary.DENOMINATOR) / 100;
        MAX_PERFORMANCE_FEE = (50 * CommonLibrary.DENOMINATOR) / 100;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IERC20RootVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return DelayedProtocolParams({managementFeeChargeDelay: 0, oracle: IOracle(address(0))});
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function delayedProtocolPerVaultParams(uint256 nft) external view returns (DelayedProtocolPerVaultParams memory) {
        if (_delayedProtocolPerVaultParams[nft].length == 0) {
            return DelayedProtocolPerVaultParams({protocolFee: 0});
        }
        return abi.decode(_delayedProtocolPerVaultParams[nft], (DelayedProtocolPerVaultParams));
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function stagedDelayedProtocolPerVaultParams(uint256 nft)
        external
        view
        returns (DelayedProtocolPerVaultParams memory)
    {
        if (_stagedDelayedProtocolPerVaultParams[nft].length == 0) {
            return DelayedProtocolPerVaultParams({protocolFee: 0});
        }
        return abi.decode(_stagedDelayedProtocolPerVaultParams[nft], (DelayedProtocolPerVaultParams));
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        if (_stagedDelayedStrategyParams[nft].length == 0) {
            return
                DelayedStrategyParams({
                    strategyTreasury: address(0),
                    strategyPerformanceTreasury: address(0),
                    privateVault: false,
                    managementFee: 0,
                    performanceFee: 0
                });
        }
        return abi.decode(_stagedDelayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function operatorParams() external view returns (OperatorParams memory) {
        if (_operatorParams.length == 0) {
            return OperatorParams({disableDeposit: false});
        }
        return abi.decode(_operatorParams, (OperatorParams));
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        if (_delayedStrategyParams[nft].length == 0) {
            return
                DelayedStrategyParams({
                    strategyTreasury: address(0),
                    strategyPerformanceTreasury: address(0),
                    privateVault: false,
                    managementFee: 0,
                    performanceFee: 0
                });
        }
        return abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function strategyParams(uint256 nft) external view returns (StrategyParams memory) {
        if (_strategyParams[nft].length == 0) {
            return StrategyParams({tokenLimitPerAddress: 0, tokenLimit: 0});
        }
        return abi.decode(_strategyParams[nft], (StrategyParams));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IERC20RootVaultGovernance).interfaceId == interfaceId;
    }

    function CONTRACT_NAME_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_NAME));
    }

    function CONTRACT_VERSION_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_VERSION));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IERC20RootVaultGovernance
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external {
        require(params.managementFee <= MAX_MANAGEMENT_FEE, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(params.performanceFee <= MAX_PERFORMANCE_FEE, ExceptionsLibrary.LIMIT_OVERFLOW);
        _stageDelayedStrategyParams(nft, abi.encode(params));
        emit StageDelayedStrategyParams(tx.origin, msg.sender, nft, params, _delayedStrategyParamsTimestamp[nft]);
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function commitDelayedStrategyParams(uint256 nft) external {
        _commitDelayedStrategyParams(nft);
        emit CommitDelayedStrategyParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams))
        );
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function stageDelayedProtocolPerVaultParams(uint256 nft, DelayedProtocolPerVaultParams calldata params) external {
        require(params.protocolFee <= MAX_PROTOCOL_FEE, ExceptionsLibrary.LIMIT_OVERFLOW);
        _stageDelayedProtocolPerVaultParams(nft, abi.encode(params));
        emit StageDelayedProtocolPerVaultParams(
            tx.origin,
            msg.sender,
            nft,
            params,
            _delayedStrategyParamsTimestamp[nft]
        );
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function commitDelayedProtocolPerVaultParams(uint256 nft) external {
        _commitDelayedProtocolPerVaultParams(nft);
        emit CommitDelayedProtocolPerVaultParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedProtocolPerVaultParams[nft], (DelayedProtocolPerVaultParams))
        );
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external {
        _setStrategyParams(nft, abi.encode(params));
        emit SetStrategyParams(tx.origin, msg.sender, nft, params);
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function setOperatorParams(OperatorParams calldata params) external {
        _setOperatorParams(abi.encode(params));
        emit SetOperatorParams(tx.origin, msg.sender, params);
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IERC20RootVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_,
        address owner_
    ) external returns (IERC20RootVault vault, uint256 nft) {
        address vaddr;
        IVaultRegistry registry = _internalParams.registry;
        (vaddr, nft) = _createVault(owner_);
        vault = IERC20RootVault(vaddr);
        for (uint256 i = 0; i < subvaultNfts_.length; i++) {
            // RootVault is not yet initialized so we cannot use safeTransferFrom here
            registry.transferFrom(msg.sender, vaddr, subvaultNfts_[i]);
        }
        vault.initialize(nft, vaultTokens_, strategy_, subvaultNfts_);
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new DelayedProtocolPerVaultParams are staged for commit
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedProtocolPerVaultParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedProtocolPerVaultParams params,
        uint256 when
    );

    /// @notice Emitted when new DelayedProtocolPerVaultParams are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that are committed
    event CommitDelayedProtocolPerVaultParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedProtocolPerVaultParams params
    );

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

    /// @notice Emitted when new StrategyParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that are set
    event SetStrategyParams(address indexed origin, address indexed sender, uint256 indexed nft, StrategyParams params);

    /// @notice Emitted when new OperatorParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params New params that are set
    event SetOperatorParams(address indexed origin, address indexed sender, OperatorParams params);

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
}
