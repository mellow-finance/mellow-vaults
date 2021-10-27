// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IGatewayVaultGovernance.sol";
import "./VaultGovernance.sol";

contract GatewayVaultGovernance is IGatewayVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract
    /// @param internalParams_ Initial Internal Params
    /// @param delayedStrategyParams_ Initial Delayed Strategy Params
    /// @param strategyParams_ Initial Strategy Params
    constructor(
        InternalParams memory internalParams_,
        DelayedStrategyParams memory delayedStrategyParams_,
        StrategyParams memory strategyParams_
    ) VaultGovernance(internalParams_) {}

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
        _stageDelayedStrategyParams(nft, abi.encode(params));
        emit StageDelayedStrategyParams(tx.origin, msg.sender, nft, params, _delayedStrategyParamsTimestamp[nft]);
    }

    function strategyTreasury(uint256 nft) external view override returns (address) {
        return delayedStrategyParams(nft).strategyTreasury;
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
