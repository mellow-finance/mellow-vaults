// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./DefaultAccessControl.sol";
import "./libraries/Common.sol";

import "./interfaces/IVaultManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultGovernance.sol";

contract VaultGovernance is IVaultGovernance, DefaultAccessControl {
    IVaultManager private _vaultManager;
    IVaultManager private _pendingVaultManager;
    uint256 private _pendingVaultManagerTimestamp;
    address private _strategyTreasury;
    address private _pendingStrategyTreasury;
    uint256 private _pendingStrategyTreasuryTimestamp;
    address[] private _tokens;
    mapping(address => bool) private _vaultTokensIndex;

    /// @notice Creates a new contract
    /// @param tokens A set of tokens that will be managed by the Vault
    /// @param manager Reference to Gateway Vault Manager
    /// @param treasury Strategy treasury address that will be used to collect Strategy Performance Fee
    /// @param admin Admin of the Vault
    constructor(
        address[] memory tokens,
        IVaultManager manager,
        address treasury,
        address admin
    ) DefaultAccessControl(admin) {
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length > 0, "TL");
        require(tokens.length <= manager.governanceParams().protocolGovernance.maxTokensPerVault(), "MTL");
        _vaultManager = manager;
        _strategyTreasury = treasury;
        _tokens = tokens;
        for (uint256 i = 0; i < tokens.length; i++) {
            _vaultTokensIndex[tokens[i]] = true;
        }
    }

    // -------------------  PUBLIC, VIEW  -------------------

    function isProtocolAdmin(address sender) public view returns (bool) {
        return _vaultManager.governanceParams().protocolGovernance.isAdmin(sender);
    }

    /// @inheritdoc IVaultGovernance
    function vaultTokens() public view returns (address[] memory) {
        return _tokens;
    }

    /// @inheritdoc IVaultGovernance
    function isVaultToken(address token) public view returns (bool) {
        return _vaultTokensIndex[token];
    }

    /// @inheritdoc IVaultGovernance
    function vaultManager() public view returns (IVaultManager) {
        return _vaultManager;
    }

    /// @inheritdoc IVaultGovernance
    function pendingVaultManager() external view returns (IVaultManager) {
        return _pendingVaultManager;
    }

    /// @inheritdoc IVaultGovernance
    function pendingVaultManagerTimestamp() external view returns (uint256) {
        return _pendingVaultManagerTimestamp;
    }

    /// @inheritdoc IVaultGovernance
    function strategyTreasury() public view returns (address) {
        return _strategyTreasury;
    }

    /// @inheritdoc IVaultGovernance
    function pendingStrategyTreasury() external view returns (address) {
        return _pendingStrategyTreasury;
    }

    /// @inheritdoc IVaultGovernance
    function pendingStrategyTreasuryTimestamp() external view returns (uint256) {
        return _pendingStrategyTreasuryTimestamp;
    }

    // -------------------  PUBLIC, MUTATING, PROTOCOL ADMIN  -------------------

    /// @inheritdoc IVaultGovernance
    function setPendingVaultManager(IVaultManager manager) external {
        require(isProtocolAdmin(msg.sender), "PADM");
        require(address(manager) != address(0), "ZMG");
        _pendingVaultManager = manager;
        _pendingVaultManagerTimestamp = _vaultManager.governanceParams().protocolGovernance.governanceDelay();
        emit SetPendingVaultManager(manager);
    }

    /// @inheritdoc IVaultGovernance
    function commitVaultManager() external {
        require(isProtocolAdmin(msg.sender), "PADM");
        require(_pendingVaultManagerTimestamp > 0, "NULL");
        require(block.timestamp > _pendingVaultManagerTimestamp, "TV");
        _vaultManager = _pendingVaultManager;
        emit CommitVaultManager(_vaultManager);
    }

    // -------------------  PUBLIC, MUTATING, ADMIN  -------------------

    /// @inheritdoc IVaultGovernance
    function setPendingStrategyTreasury(address treasury) external {
        require(isAdmin(msg.sender), "AG");
        require(address(treasury) != address(0), "ZMG");
        _pendingStrategyTreasury = treasury;
        _pendingStrategyTreasuryTimestamp = _vaultManager.governanceParams().protocolGovernance.governanceDelay();
        emit SetPendingStrategyTreasury(treasury);
    }

    /// @inheritdoc IVaultGovernance
    function commitStrategyTreasury() external {
        require(isAdmin(msg.sender), "AG");
        require(_pendingStrategyTreasuryTimestamp > 0, "NULL");
        require(block.timestamp > _pendingStrategyTreasuryTimestamp, "TV");
        _strategyTreasury = _pendingStrategyTreasury;
        emit CommitStrategyTreasury(_strategyTreasury);
    }

    // -------------------  PRIVATE, VIEW  -------------------
}
