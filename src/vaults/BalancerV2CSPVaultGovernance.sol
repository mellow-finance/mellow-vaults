// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/vaults/IBalancerV2VaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all BalancerV2 Vaults params and can deploy a new BalancerV2 Vault.
contract BalancerV2CSPVaultGovernance is ContractMeta, IBalancerV2VaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IBalancerV2VaultGovernance
    function strategyParams(uint256 nft) external view returns (StrategyParams memory) {
        if (_strategyParams[nft].length == 0) {
            return
                StrategyParams({
                    swaps: new IBalancerVault.BatchSwapStep[](0),
                    assets: new IAsset[](0),
                    funds: IBalancerVault.FundManagement({
                        sender: address(0),
                        fromInternalBalance: false,
                        recipient: payable(address(0)),
                        toInternalBalance: false
                    }),
                    rewardOracle: IAggregatorV3(address(0)),
                    underlyingOracle: IAggregatorV3(address(0)),
                    slippageD: 0
                });
        }
        return abi.decode(_strategyParams[nft], (StrategyParams));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IBalancerV2VaultGovernance).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IBalancerV2VaultGovernance
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external {
        require(
            params.swaps.length > 0 &&
                params.assets.length > 1 &&
                address(params.rewardOracle) != address(0) &&
                address(params.underlyingOracle) != address(0),
            ExceptionsLibrary.INVALID_VALUE
        );
        _setStrategyParams(nft, abi.encode(params));
        emit SetStrategyParams(tx.origin, msg.sender, nft, params);
    }

    /// @inheritdoc IBalancerV2VaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address pool_,
        address balancerVault_,
        address stakingLiquidityGauge_,
        address balancerMinter_
    ) external returns (IBalancerV2Vault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IBalancerV2Vault(vaddr);

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
        return bytes32("BalancerV2CSPVaultGovernance");
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
