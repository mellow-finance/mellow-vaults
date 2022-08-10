// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IPerpVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

contract PerpVaultGovernance is ContractMeta, IPerpVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        require(address(delayedProtocolParams_.vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(delayedProtocolParams_.clearingHouse) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(delayedProtocolParams_.accountBalance) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.vusdcAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.usdcAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(delayedProtocolParams_.uniV3FactoryAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IPerpVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IPerpVaultGovernance).interfaceId;
    }

    /// @inheritdoc IPerpVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return
                DelayedProtocolParams({
                    vault: IPerpInternalVault(address(0)),
                    clearingHouse: IClearingHouse(address(0)),
                    accountBalance: IAccountBalance(address(0)),
                    vusdcAddress: address(0),
                    usdcAddress: address(0),
                    uniV3FactoryAddress: address(0),
                    maxProtocolLeverage: 0
                });
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IPerpVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        require(address(params.vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(params.clearingHouse) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(params.accountBalance) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.vusdcAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.usdcAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.uniV3FactoryAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IPerpVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @inheritdoc IPerpVaultGovernance
    function createVault(
        address owner_,
        address baseToken_,
        uint256 leverageMultiplierD_,
        bool isLongBaseToken_
    ) external returns (IPerpFuturesVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        IPerpFuturesVault perpVault = IPerpFuturesVault(vaddr);
        perpVault.initialize(nft, baseToken_, leverageMultiplierD_, isLongBaseToken_);
        vault = IPerpFuturesVault(vaddr);
        address[] memory vaultTokens = new address[](1);
        vaultTokens[0] = baseToken_;
        emit DeployedVault(
            tx.origin,
            msg.sender,
            vaultTokens,
            abi.encode(leverageMultiplierD_, isLongBaseToken_),
            owner_,
            vaddr,
            nft
        );
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("PerpVaultGovernance");
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
