// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/vaults/IQuickSwapVaultGovernance.sol";
import "../interfaces/vaults/IQuickSwapVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all QuickSwap Vaults params and can deploy a new QuickSwap Vault.
contract QuickSwapVaultGovernance is ContractMeta, IQuickSwapVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IQuickSwapVaultGovernance
    function strategyParams(uint256 nft) external view returns (StrategyParams memory) {
        if (_strategyParams[nft].length == 0) {
            return
                StrategyParams({
                    key: IIncentiveKey.IncentiveKey({
                        rewardToken: IERC20Minimal(address(0)),
                        bonusRewardToken: IERC20Minimal(address(0)),
                        pool: IAlgebraPool(address(0)),
                        startTime: 0,
                        endTime: 0
                    }),
                    bonusTokenToUnderlying: address(0),
                    rewardTokenToUnderlying: address(0),
                    swapSlippageD: 0,
                    rewardPoolTimespan: 0
                });
        }
        return abi.decode(_strategyParams[nft], (StrategyParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IQuickSwapVaultGovernance).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IQuickSwapVaultGovernance
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external {
        require(params.bonusTokenToUnderlying != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.rewardTokenToUnderlying != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.swapSlippageD < 10**9, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(address(params.key.rewardToken) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(params.key.bonusRewardToken) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(params.key.pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.key.startTime > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.key.endTime > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.rewardPoolTimespan > 0, ExceptionsLibrary.VALUE_ZERO);
        _setStrategyParams(nft, abi.encode(params));
        emit SetStrategyParams(tx.origin, msg.sender, nft, params);
    }

    /// @inheritdoc IQuickSwapVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address erc20Vault_
    ) external returns (IQuickSwapVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IQuickSwapVault(vaddr);
        vault.initialize(nft, erc20Vault_, vaultTokens_);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, abi.encode(erc20Vault_), owner_, vaddr, nft);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("QuickSwapVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.1.0");
    }

    // --------------------------  EVENTS  --------------------------
    /// @notice Emitted when new StrategyParams are set
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New set params
    event SetStrategyParams(address indexed origin, address indexed sender, uint256 indexed nft, StrategyParams params);
}
