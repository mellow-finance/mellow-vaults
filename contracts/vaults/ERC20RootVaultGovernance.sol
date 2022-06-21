// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IIntegrationVault.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";
import "../interfaces/utils/IERC20RootVaultHelper.sol";

/// @notice Governance that manages all Lp Issuers params and can deploy a new LpIssuer Vault.
contract ERC20RootVaultGovernance is ContractMeta, IERC20RootVaultGovernance, VaultGovernance {
    /// @inheritdoc IERC20RootVaultGovernance
    uint256 public constant MAX_PROTOCOL_FEE = 5 * 10**7; // 5%
    /// @inheritdoc IERC20RootVaultGovernance
    uint256 public constant MAX_MANAGEMENT_FEE = 10 * 10**7; // 10%
    /// @inheritdoc IERC20RootVaultGovernance
    uint256 public constant MAX_PERFORMANCE_FEE = 50 * 10**7; // 50%

    IERC20RootVaultHelper public immutable helper;

    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(
        InternalParams memory internalParams_,
        DelayedProtocolParams memory delayedProtocolParams_,
        IERC20RootVaultHelper helper_
    ) VaultGovernance(internalParams_) {
        require(address(delayedProtocolParams_.oracle) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(helper_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        helper = helper_;
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
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
                    performanceFee: 0,
                    depositCallbackAddress: address(0),
                    withdrawCallbackAddress: address(0)
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
                    performanceFee: 0,
                    depositCallbackAddress: address(0),
                    withdrawCallbackAddress: address(0)
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

    // @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IERC20RootVaultGovernance).interfaceId == interfaceId;
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
        require(address(params.oracle) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
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
        require(subvaultNfts_.length > 0, ExceptionsLibrary.EMPTY_LIST);
        for (uint256 i = 0; i < subvaultNfts_.length; i++) {
            uint256 subvaultNft = subvaultNfts_[i];
            require(subvaultNft > 0, ExceptionsLibrary.VALUE_ZERO);
            address subvault = registry.vaultForNft(subvaultNft);
            require(subvault != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            require(
                IIntegrationVault(subvault).supportsInterface(type(IIntegrationVault).interfaceId),
                ExceptionsLibrary.INVALID_INTERFACE
            );
            address[] memory subvaultTokens = IIntegrationVault(subvault).vaultTokens();
            if (i == 0) {
                // The zero-vault must have the same tokens as ERC20RootVault
                require(vaultTokens_.length == subvaultTokens.length, ExceptionsLibrary.INVALID_LENGTH);
                require(
                    IERC165(subvault).supportsInterface(type(IERC20Vault).interfaceId),
                    ExceptionsLibrary.INVALID_INTERFACE
                );
            }
            uint256 subvaultTokenId = 0;
            for (
                uint256 tokenId = 0;
                tokenId < vaultTokens_.length && subvaultTokenId < subvaultTokens.length;
                ++tokenId
            ) {
                if (subvaultTokens[subvaultTokenId] == vaultTokens_[tokenId]) {
                    subvaultTokenId++;
                }
            }
            require(subvaultTokenId == subvaultTokens.length, ExceptionsLibrary.INVALID_TOKEN);

            // RootVault is not yet initialized so we cannot use safeTransferFrom here
            registry.transferFrom(msg.sender, vaddr, subvaultNfts_[i]);
        }
        vault.initialize(nft, vaultTokens_, strategy_, subvaultNfts_, helper);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("ERC20RootVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
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
