// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IPerpVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

contract PerpVaultGovernance is ContractMeta, IPerpVaultGovernance, VaultGovernance {
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

    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        // params are initialized in constructor, so cannot be 0
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IPerpVaultGovernance).interfaceId;
    }

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

    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        require(address(params.vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(params.clearingHouse) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(params.accountBalance) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.vusdcAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.usdcAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.uniV3FactoryAddress != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _stageDelayedProtocolParams(abi.encode(params));
    }

    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
    }

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
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("PerpVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
