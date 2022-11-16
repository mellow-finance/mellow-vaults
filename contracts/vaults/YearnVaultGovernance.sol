// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IYearnVaultGovernance.sol";
import "../interfaces/vaults/IYearnVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Aave Vaults params and can deploy a new Aave Vault.
contract YearnVaultGovernance is ContractMeta, IYearnVaultGovernance, VaultGovernance {
    mapping(address => address) private _yTokens;

    /// @notice Creates a new contract
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        require(address(delayedProtocolParams_.yearnVaultRegistry) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IYearnVaultGovernance
    function yTokenForToken(address token) external view returns (address) {
        address yToken = _yTokens[token];
        if (yToken != address(0)) {
            return yToken;
        }
        IYearnProtocolVaultRegistry yearnRegistry = delayedProtocolParams().yearnVaultRegistry;
        try yearnRegistry.latestVault(token) returns (address _vault) {
            return _vault;
        } catch (bytes memory) {
            return address(0);
        }
    }

    /// @inheritdoc IYearnVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return DelayedProtocolParams({yearnVaultRegistry: IYearnProtocolVaultRegistry(address(0))});
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IYearnVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IYearnVaultGovernance).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IYearnVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        require(address(params.yearnVaultRegistry) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IYearnVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IYearnVaultGovernance
    function setYTokenForToken(address token, address yToken) external {
        _requireProtocolAdmin();
        _yTokens[token] = yToken;
        emit SetYToken(tx.origin, msg.sender, token, yToken);
    }

    /// @inheritdoc IYearnVaultGovernance
    function createVault(address[] memory vaultTokens_, address owner_)
        external
        returns (IYearnVault vault, uint256 nft)
    {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IYearnVault(vaddr);
        vault.initialize(nft, vaultTokens_);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, "", owner_, vaddr, nft);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("YearnVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new yToken is set
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param token ERC-20 token for the yToken
    /// @param yToken yToken for ERC-20 token
    event SetYToken(address indexed origin, address indexed sender, address indexed token, address yToken);

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
