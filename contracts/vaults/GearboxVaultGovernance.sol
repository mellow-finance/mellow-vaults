// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IGearboxVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

contract PerpVaultGovernance is ContractMeta, IGearboxVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IGearboxVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IGearboxVaultGovernance).interfaceId;
    }

    /// @inheritdoc IGearboxVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return
                DelayedProtocolParams({
                    kek: 0
                });
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IGearboxVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams memory params) external {
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IGearboxVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IGearboxVaultGovernance
    function createVault(
        address owner_,
        address primaryToken_,
        address secondaryToken_,
        address curveAdapter_,
        address convexAdapter_,
        address facade_,
        uint256 convexPoolId_
    ) external returns (IGearboxVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        IGearboxVault gearboxVault = IGearboxVault(vaddr);
        gearboxVault.initialize(nft, primaryToken_, secondaryToken_, curveAdapter_, convexAdapter_, facade_, convexPoolId_);
        vault = IGearboxVault(vaddr);
        address[] memory vaultTokens = new address[](1);
        vaultTokens[0] = primaryToken_;
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("GearboxVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
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