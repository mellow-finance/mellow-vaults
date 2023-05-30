// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../external/kyber/periphery/IBasePositionManager.sol";
import "../external/kyber/IKyberSwapElasticLM.sol";
import "../external/kyber/periphery/IRouter.sol";
import "../oracles/IOracle.sol";
import "./IVaultGovernance.sol";
import "./IKyberVault.sol";

interface IKyberVaultGovernance is IVaultGovernance {

    struct StrategyParams {
        IKyberSwapElasticLM farm;
        bytes[] paths;
        uint256 pid;
    }

    /// @notice Delayed Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        uint24 fee_
    ) external returns (IKyberVault vault, uint256 nft);
}
