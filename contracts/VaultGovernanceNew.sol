// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract VaultGovernanceNew {
    struct InternalParams {
        IProtocolGovernance protocolGovernance;
        IERC721 registry;
    }

    InternalParams private _internalParams;
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

    constructor(InternalParams memory internalParams_) {
        _internalParams = internalParams_;
    }

    // -------------------  PUBLIC, VIEW  -------------------

    /// @notice Timestamp in unix time seconds after which staged Delayed Strategy Params could be committed
    /// @param nft Nft of the vault
    function delayedStrategyParamsTimestamp(uint256 nft) external view returns (uint256) {
        return _delayedStrategyParamsTimestamp[nft];
    }

    /// @notice Timestamp in unix time seconds after which staged Delayed Protocol Params could be committed
    function delayedProtocolParamsTimestamp() external view returns (uint256) {
        return _delayedProtocolParamsTimestamp;
    }

    /// @notice Timestamp in unix time seconds after which staged Protocol Governance could be committed
    function internalParamsTimestamp() external view returns (uint256) {
        return _internalParamsTimestamp;
    }

    /// @notice Reference to Protocol Governance
    function internalParams() external view returns (InternalParams memory) {
        return _internalParams;
    }

    /// @notice Staged new reference to Protocol Governance
    /// @dev The internalParams could be committed after protocolGovernanceTimestamp
    function stagedInternalParams() external view returns (InternalParams memory) {
        return _stagedInternalParams;
    }

    // -------------------  PUBLIC  -------------------

    /// @notice Stage new Internal Params
    /// @param newParams New Internal Params
    function stageInternalParams(InternalParams memory newParams) internal {
        _requireProtocolAdmin();
        _stagedInternalParams = newParams;
        _internalParamsTimestamp = block.timestamp + _internalParams.protocolGovernance.governanceDelay();
        emit StagedInternalParams(msg.sender, newParams, _internalParamsTimestamp);
    }

    /// @notice Commit staged Internal Params
    function commitInternalParams() internal {
        _requireProtocolAdmin();
        require(_internalParamsTimestamp > 0, "NULL");
        require(block.timestamp > _internalParamsTimestamp, "TS");
        _internalParams = _stagedInternalParams;
        delete _internalParamsTimestamp;
        emit CommitedInternalParams(msg.sender, _internalParams);
    }

    // -------------------  INTERNAL  -------------------

    /// @notice Set delayed strategy params
    /// @dev Should require nft > 0
    /// @param nft Nft of the vault
    /// @param params New params
    function _stageDelayedStrategyParams(uint256 nft, bytes calldata params) internal {
        _requireAtLeastStrategy(nft);
        _stagedDelayedStrategyParams[nft] = params;
        _delayedStrategyParamsTimestamp[nft] = block.timestamp + _internalParams.protocolGovernance.governanceDelay();
    }

    /// @notice Commit delayed strategy params
    function _commitDelayedStrategyParams(uint256 nft) internal {
        _requireAtLeastStrategy(nft);
        require(_delayedStrategyParamsTimestamp[nft] > 0, "NULL");
        require(block.timestamp > _delayedStrategyParamsTimestamp[nft], "TS");
        _delayedStrategyParams[nft] = _stagedDelayedStrategyParams[nft];
        delete _delayedStrategyParamsTimestamp[nft];
    }

    /// @notice Set delayed protocol params
    /// @param params New params
    function _stageDelayedProtocolParams(bytes calldata params) internal {
        _requireProtocolAdmin();
        _stagedDelayedProtocolParams = params;
        _delayedProtocolParamsTimestamp = block.timestamp + _internalParams.protocolGovernance.governanceDelay();
    }

    /// @notice Commit delayed protocol params
    /// @dev VaultRegistry guarantees `nft > 0`, so `nft == 0` is reserved for params common for all vaults
    function _commitDelayedProtocolParams() internal {
        _requireProtocolAdmin();
        require(_delayedProtocolParamsTimestamp > 0, "NULL");
        require(block.timestamp > _delayedProtocolParamsTimestamp, "TS");
        _delayedProtocolParams = _stagedDelayedProtocolParams;
        delete _delayedProtocolParamsTimestamp;
    }

    /// @notice Set immediate strategy params
    /// @dev Should require nft > 0
    /// @param nft Nft of the vault
    /// @param params New params
    function _setStrategyParams(uint256 nft, bytes calldata params) internal {
        _requireAtLeastStrategy(nft);
        _strategyParams[nft] = params;
    }

    /// @notice Set immediate protocol params
    /// @dev VaultRegistry guarantees `nft > 0`, so `nft == 0` is reserved for params common for all vaults
    /// @param params New params
    function _setProtocolParams(bytes calldata params) internal {
        _requireProtocolAdmin();
        _protocolParams = params;
    }

    function _requireAtLeastStrategy(uint256 nft) private view {
        require(
            (_internalParams.registry.getApproved(nft) == msg.sender) ||
                _internalParams.protocolGovernance.isAdmin(msg.sender),
            "RST"
        );
    }

    function _requireProtocolAdmin() private view {
        require(_internalParams.protocolGovernance.isAdmin(msg.sender), "ADM");
    }

    event StagedInternalParams(address who, InternalParams newParams, uint256 start);
    event CommitedInternalParams(address who, InternalParams newParams);
}
