// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";
import "../interfaces/vaults/IAaveVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Aave Vaults params and can deploy a new Aave Vault.
contract AaveVaultGovernance is IContractMeta, IAaveVaultGovernance, VaultGovernance {
    bytes32 public constant CONTRACT_NAME = "AaveVaultGovernance";
    uint256 public constant CONTRACT_VERSION = 1;

    uint256 public immutable MAX_ESTIMATED_AAVE_APY;

    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        MAX_ESTIMATED_AAVE_APY = CommonLibrary.DENOMINATOR;
        require(address(delayedProtocolParams_.lendingPool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.estimatedAaveAPY != 0, ExceptionsLibrary.VALUE_ZERO);
        require(delayedProtocolParams_.estimatedAaveAPY <= MAX_ESTIMATED_AAVE_APY, ExceptionsLibrary.LIMIT_OVERFLOW);

        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IAaveVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IAaveVaultGovernance).interfaceId;
    }

    /// @inheritdoc IAaveVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return DelayedProtocolParams({lendingPool: ILendingPool(address(0)), estimatedAaveAPY: 0});
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IAaveVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        require(params.estimatedAaveAPY <= MAX_ESTIMATED_AAVE_APY, ExceptionsLibrary.LIMIT_OVERFLOW);
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IAaveVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IAaveVaultGovernance
    function createVault(address[] memory vaultTokens_, address owner_)
        external
        returns (IAaveVault vault, uint256 nft)
    {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IAaveVault(vaddr);
        vault.initialize(nft, vaultTokens_);
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
}
