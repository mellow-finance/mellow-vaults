// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IGatewayVaultGovernance.sol";
import "./interfaces/IGatewayVault.sol";
import "./VaultGovernance.sol";

contract GatewayVaultGovernance is VaultGovernance, IGatewayVaultGovernance {
    /// @notice Creates a new contract
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    /// @inheritdoc IGatewayVaultGovernance
    function delayedStrategyParams(uint256 nft) public view returns (DelayedStrategyParams memory) {
        return abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IGatewayVaultGovernance
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        return abi.decode(_stagedDelayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IGatewayVaultGovernance
    function strategyParams(uint256 nft) external view returns (StrategyParams memory) {
        return abi.decode(_strategyParams[nft], (StrategyParams));
    }

    /// @inheritdoc IGatewayVaultGovernance
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external {
        IVault vault = IVault(_internalParams.registry.vaultForNft(nft));
        require((params.redirects.length == 0) || (params.redirects.length == vault.vaultTokens().length), "RL");
        _stageDelayedStrategyParams(nft, abi.encode(params));
        emit StageDelayedStrategyParams(tx.origin, msg.sender, nft, params, _delayedStrategyParamsTimestamp[nft]);
    }

    /// @inheritdoc IVaultGovernance
    function strategyTreasury(uint256 nft) external view override(IVaultGovernance, VaultGovernance) returns (address) {
        return delayedStrategyParams(nft).strategyTreasury;
    }

    /// @notice Deploy a new vault
    /// @param vaultTokens ERC20 tokens under vault management
    /// @param options Abi encoded uint256[] - an array of Nfts of subvaults. It is required that each nft subvault is approved by the caller to this address.
    /// @param strategy Strategy that will be approved to manage subvaults
    /// @return vault Address of the new vault
    /// @return nft Nft of the vault in the vault registry
    function deployVault(
        address[] memory vaultTokens,
        bytes memory options,
        address strategy
    ) public override(VaultGovernance, IVaultGovernance) returns (IVault vault, uint256 nft) {
        (vault, nft) = super.deployVault(vaultTokens, "", msg.sender);
        uint256[] memory subvaultNfts = abi.decode(options, (uint256[]));
        IVaultRegistry registry = _internalParams.registry;
        for (uint256 i = 0; i < subvaultNfts.length; i++) {
            registry.transferFrom(msg.sender, address(this), subvaultNfts[i]);
            registry.approve(strategy, subvaultNfts[i]);
        }
        IGatewayVault(address(vault)).addSubvaults(subvaultNfts);
    }

    /// @inheritdoc IGatewayVaultGovernance
    function commitDelayedStrategyParams(uint256 nft) external {
        _commitDelayedStrategyParams(nft);
        emit CommitDelayedStrategyParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams))
        );
    }

    /// @inheritdoc IGatewayVaultGovernance
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external {
        _setStrategyParams(nft, abi.encode(params));
        emit SetStrategyParams(tx.origin, msg.sender, nft, params);
    }
}
