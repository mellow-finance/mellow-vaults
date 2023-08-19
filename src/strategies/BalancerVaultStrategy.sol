// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/utils/ILpCallback.sol";

import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IBalancerV2VaultGovernance.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";

contract BalancerVaultStrategy is ContractMeta, ILpCallback, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    IERC20Vault public erc20Vault;
    IBalancerV2Vault public subvault;
    address public swapRouter;

    address[] private _rewardTokens;

    function rewardTokens() public view returns (address[] memory) {
        return _rewardTokens;
    }

    constructor() {
        DefaultAccessControlLateInit.init(address(this));
    }

    function initialize(
        address admin,
        IERC20Vault erc20Vault_,
        address subvault_,
        address swapRouter_
    ) external {
        erc20Vault = erc20Vault_;
        subvault = IBalancerV2Vault(subvault_);
        swapRouter = swapRouter_;

        DefaultAccessControlLateInit(address(this)).init(admin);
    }

    function compound(bytes[] memory swapParams, uint256 deadline) external returns (uint256[] memory tokenAmounts) {
        _requireAtLeastOperator();
        require(deadline < block.timestamp, ExceptionsLibrary.LIMIT_OVERFLOW);

        address[] memory rewardTokens_ = _rewardTokens;
        require(swapParams.length == rewardTokens_.length, ExceptionsLibrary.INVALID_LENGTH);

        try subvault.claimBalancerRewardToken() returns (uint256) {} catch {}
        try subvault.claimRewards() {} catch {}

        for (uint256 i = 0; i < swapParams.length; i++) {
            uint256 balance = IERC20(rewardTokens_[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(rewardTokens_[i]).safeIncreaseAllowance(swapRouter, balance);
                (bool success, ) = swapRouter.call(swapParams[i]);
                if (!success) revert("Swap of reward token failed");
                IERC20(rewardTokens_[i]).safeApprove(swapRouter, 0);
            }
        }

        address[] memory tokens = erc20Vault.vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                tokenAmounts[i] = balance;
                IERC20(tokens[i]).safeTransfer(address(erc20Vault), balance);
            }
        }
    }

    function setRewardTokens(address[] memory rewardTokens_) external {
        _requireAdmin();
        _rewardTokens = rewardTokens_;
    }

    function setStrategyParams(IBalancerV2VaultGovernance.StrategyParams memory strategyParams) external {
        _requireAdmin();
        IBalancerV2VaultGovernance(address(subvault.vaultGovernance())).setStrategyParams(
            subvault.nft(),
            strategyParams
        );
    }

    /// @inheritdoc ILpCallback
    function depositCallback() external {
        (uint256[] memory tokenAmounts, ) = erc20Vault.tvl();
        if (tokenAmounts[0] > 0 || tokenAmounts[1] > 0) {
            erc20Vault.pull(address(subvault), erc20Vault.vaultTokens(), tokenAmounts, "");
        }
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback() external {}

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("BalancerVaultStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
