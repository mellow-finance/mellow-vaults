// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultGovernance.sol";

/// @notice Internal contract for managing different params
/// @dev The contract should be overriden by the concrete VaultGovernanceOld,
/// define different params structs and use abi.decode / abi.encode to serialize
/// to bytes in this contract. It also should emit events on params change.
abstract contract VaultGovernance is IVaultGovernance {
    InternalParams internal _internalParams;
    InternalParams private _stagedInternalParams;
    uint256 internal _internalParamsTimestamp;

    mapping(uint256 => bytes) internal _delayedStrategyParams;
    mapping(uint256 => bytes) internal _stagedDelayedStrategyParams;
    mapping(uint256 => uint256) internal _delayedStrategyParamsTimestamp;

    bytes internal _delayedProtocolParams;
    bytes internal _stagedDelayedProtocolParams;
    uint256 internal _delayedProtocolParamsTimestamp;

    mapping(uint256 => bytes) internal _strategyParams;
    bytes internal _protocolParams;

    IVaultFactory public factory;
    bool public initialized;

    /// @notice Creates a new contract
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) {
        _internalParams = internalParams_;
    }

    // -------------------  PUBLIC, VIEW  -------------------

    /// @inheritdoc IVaultGovernance
    function delayedStrategyParamsTimestamp(uint256 nft) external view returns (uint256) {
        return _delayedStrategyParamsTimestamp[nft];
    }

    /// @inheritdoc IVaultGovernance
    function delayedProtocolParamsTimestamp() external view returns (uint256) {
        return _delayedProtocolParamsTimestamp;
    }

    /// @inheritdoc IVaultGovernance
    function internalParamsTimestamp() external view returns (uint256) {
        return _internalParamsTimestamp;
    }

    /// @inheritdoc IVaultGovernance
    function internalParams() external view returns (InternalParams memory) {
        return _internalParams;
    }

    /// @inheritdoc IVaultGovernance
    function stagedInternalParams() external view returns (InternalParams memory) {
        return _stagedInternalParams;
    }

    /// @inheritdoc IVaultGovernance
    function strategyTreasury(uint256 nft) external view virtual returns (address);

    // -------------------  PUBLIC, MUTATING  -------------------

    /// @inheritdoc IVaultGovernance
    function initialize(IVaultFactory factory_) external {
        require(!initialized, "INIT");
        factory = factory_;
        initialized = true;
    }

    /// @inheritdoc IVaultGovernance
    function deployVault(
        address[] memory vaultTokens,
        bytes memory options,
        address owner
    ) public virtual returns (IVault vault, uint256 nft) {
        require(initialized, "INIT");
        IProtocolGovernance protocolGovernance = _internalParams.protocolGovernance;
        require(protocolGovernance.permissionless() || protocolGovernance.isAdmin(msg.sender), "POA");
        vault = factory.deployVault(vaultTokens, options);
        nft = _internalParams.registry.registerVault(address(vault), owner);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens, options, owner, address(vault), nft);
    }

    /// @inheritdoc IVaultGovernance
    function stageInternalParams(InternalParams memory newParams, address sender) external {
        _requireProtocolAdmin(sender);
        _stagedInternalParams = newParams;
        _internalParamsTimestamp = block.timestamp + _internalParams.protocolGovernance.governanceDelay();
        emit StagedInternalParams(tx.origin, msg.sender, newParams, _internalParamsTimestamp);
    }

    /// @inheritdoc IVaultGovernance
    function commitInternalParams(address sender) external {
        _requireProtocolAdmin(sender);
        require(_internalParamsTimestamp > 0, "NULL");
        require(block.timestamp >= _internalParamsTimestamp, "TS");
        _internalParams = _stagedInternalParams;
        delete _internalParamsTimestamp;
        emit CommitedInternalParams(tx.origin, msg.sender, _internalParams);
    }

    // -------------------  INTERNAL  -------------------

    /// @notice Set Delayed Strategy Params
    /// @param nft Nft of the vault
    /// @param params New params
    function _stageDelayedStrategyParams(uint256 nft, bytes memory params, address sender) internal {
        _requireAtLeastStrategy(nft, sender);
        _stagedDelayedStrategyParams[nft] = params;
        uint256 delayFactor = _delayedStrategyParams[nft].length == 0 ? 0 : 1;
        _delayedStrategyParamsTimestamp[nft] =
            block.timestamp +
            _internalParams.protocolGovernance.governanceDelay() *
            delayFactor;
    }

    /// @notice Commit Delayed Strategy Params
    function _commitDelayedStrategyParams(uint256 nft, address sender) internal {
        _requireAtLeastStrategy(nft, sender);
        require(_delayedStrategyParamsTimestamp[nft] > 0, "NULL");
        require(block.timestamp >= _delayedStrategyParamsTimestamp[nft], "TS");
        _delayedStrategyParams[nft] = _stagedDelayedStrategyParams[nft];
        delete _delayedStrategyParamsTimestamp[nft];
    }

    /// @notice Set Delayed Protocol Params
    /// @param params New params
    function _stageDelayedProtocolParams(bytes memory params, address sender) internal {
        _requireProtocolAdmin(sender);
        uint256 delayFactor = _delayedProtocolParams.length == 0 ? 0 : 1;
        _stagedDelayedProtocolParams = params;
        _delayedProtocolParamsTimestamp =
            block.timestamp +
            _internalParams.protocolGovernance.governanceDelay() *
            delayFactor;
    }

    /// @notice Commit Delayed Protocol Params
    function _commitDelayedProtocolParams(address sender) internal {
        _requireProtocolAdmin(sender);
        require(_delayedProtocolParamsTimestamp > 0, "NULL");
        require(block.timestamp >= _delayedProtocolParamsTimestamp, "TS");
        _delayedProtocolParams = _stagedDelayedProtocolParams;
        delete _delayedProtocolParamsTimestamp;
    }

    /// @notice Set immediate strategy params
    /// @dev Should require nft > 0
    /// @param nft Nft of the vault
    /// @param params New params
    function _setStrategyParams(uint256 nft, bytes memory params, address sender) internal {
        _requireAtLeastStrategy(nft, sender);
        _strategyParams[nft] = params;
    }

    /// @notice Set immediate protocol params
    /// @param params New params
    function _setProtocolParams(bytes memory params, address sender) internal {
        _requireProtocolAdmin(sender);
        _protocolParams = params;
    }

    function _requireAtLeastStrategy(uint256 nft, address sender) private view {
        require(
            (_internalParams.protocolGovernance.isAdmin(sender) ||
                _internalParams.registry.getApproved(nft) == sender),
            "RST"
        );
    }

    function _requireProtocolAdmin(address sender) private view {
        require(_internalParams.protocolGovernance.isAdmin(sender), "ADM");
    }
}
