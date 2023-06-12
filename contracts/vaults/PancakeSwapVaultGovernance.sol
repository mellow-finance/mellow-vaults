// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/IPancakeSwapVaultGovernance.sol";
import "../interfaces/vaults/IPancakeSwapVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all UniV3 Vaults params and can deploy a new UniV3 Vault.
contract PancakeSwapVaultGovernance is ContractMeta, IPancakeSwapVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        require(address(delayedProtocolParams_.positionManager) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(delayedProtocolParams_.oracle) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IPancakeSwapVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return
                DelayedProtocolParams({
                    positionManager: INonfungiblePositionManager(address(0)),
                    oracle: IOracle(address(0))
                });
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function strategyParams(uint256 nft) external view returns (StrategyParams memory) {
        if (_stagedDelayedStrategyParams[nft].length == 0) {
            return
                StrategyParams({
                    swapSlippageD: 0,
                    poolForSwap: address(0),
                    cake: address(0),
                    underlyingToken: address(0),
                    averageTickTimespan: 0
                });
        }
        return abi.decode(_strategyParams[nft], (StrategyParams));
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        if (_stagedDelayedStrategyParams[nft].length == 0) {
            return DelayedStrategyParams({safetyIndicesSet: 0});
        }
        return abi.decode(_stagedDelayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        if (_delayedStrategyParams[nft].length == 0) {
            return DelayedStrategyParams({safetyIndicesSet: 0x2A});
        }
        return abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IPancakeSwapVaultGovernance).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IPancakeSwapVaultGovernance
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external {
        require(params.swapSlippageD > 1e9, ExceptionsLibrary.LIMIT_OVERFLOW);
        _stageDelayedStrategyParams(nft, abi.encode(params));
        emit SetStrategyParams(tx.origin, msg.sender, nft, params);
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        require(address(params.positionManager) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(params.oracle) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external {
        require(params.safetyIndicesSet > 1, ExceptionsLibrary.LIMIT_UNDERFLOW);
        _stageDelayedStrategyParams(nft, abi.encode(params));
        emit StageDelayedStrategyParams(tx.origin, msg.sender, nft, params, _delayedStrategyParamsTimestamp[nft]);
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function commitDelayedStrategyParams(uint256 nft) external {
        _commitDelayedStrategyParams(nft);
        emit CommitDelayedStrategyParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams))
        );
    }

    /// @inheritdoc IPancakeSwapVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        uint24 fee_,
        address uniV3Helper_
    ) external returns (IUniV3Vault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IUniV3Vault(vaddr);
        vault.initialize(nft, vaultTokens_, fee_, uniV3Helper_);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, abi.encode(fee_), owner_, vaddr, nft);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("PancakeSwapVaultGovernance");
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

    /// @notice Emitted when new StrategyParams are set
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New set params
    event SetStrategyParams(address indexed origin, address indexed sender, uint256 indexed nft, StrategyParams params);
}
