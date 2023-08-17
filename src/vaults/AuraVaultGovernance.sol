// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/IAuraVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all BalancerV2 Vaults params and can deploy a new BalancerV2 Vault.
contract AuraVaultGovernance is ContractMeta, IAuraVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IAuraVaultGovernance
    function strategyParams(uint256 nft) external view returns (StrategyParams memory) {
        if (_strategyParams[nft].length == 0) {
            return StrategyParams({tokensSwapParams: new SwapParams[](0)});
        }
        return abi.decode(_strategyParams[nft], (StrategyParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IAuraVaultGovernance).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IAuraVaultGovernance
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external {
        for (uint256 i = 0; i < params.tokensSwapParams.length; i++) {
            SwapParams memory params_ = params.tokensSwapParams[i];
            require(
                params_.swaps.length > 0 &&
                    params_.assets.length > 1 &&
                    address(params_.rewardOracle) != address(0) &&
                    address(params_.underlyingOracle) != address(0),
                ExceptionsLibrary.INVALID_VALUE
            );
        }
        _setStrategyParams(nft, abi.encode(params));
        emit SetStrategyParams(tx.origin, msg.sender, nft, params);
    }

    /// @inheritdoc IAuraVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address pool_,
        address balancerVault_,
        address stakingLiquidityGauge_,
        address balancerMinter_
    ) external returns (IAuraVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IAuraVault(vaddr);

        vault.initialize(nft, vaultTokens_, pool_, balancerVault_, stakingLiquidityGauge_, balancerMinter_);
        emit DeployedVault(
            tx.origin,
            msg.sender,
            vaultTokens_,
            abi.encode(pool_, balancerVault_, stakingLiquidityGauge_, balancerMinter_),
            owner_,
            vaddr,
            nft
        );
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("AuraVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when new StrategyParams are set
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New set params
    event SetStrategyParams(address indexed origin, address indexed sender, uint256 indexed nft, StrategyParams params);
}
