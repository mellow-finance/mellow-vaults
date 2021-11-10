// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IERC20VaultGovernance.sol";
import "./VaultGovernance.sol";

contract ERC20VaultGovernance is IERC20VaultGovernance, VaultGovernance {
    /// @notice Creates a new contract
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    /// @inheritdoc IERC20VaultGovernance
    function delayedStrategyParams(uint256 nft) public view returns (DelayedStrategyParams memory) {
        return abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IERC20VaultGovernance
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        return abi.decode(_stagedDelayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IERC20VaultGovernance
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external {
        _stageDelayedStrategyParams(nft, abi.encode(params), msg.sender);
        emit StageDelayedStrategyParams(tx.origin, msg.sender, nft, params, _delayedStrategyParamsTimestamp[nft]);
    }

    function strategyTreasury(uint256 nft) external view override(IVaultGovernance, VaultGovernance) returns (address) {
        return delayedStrategyParams(nft).strategyTreasury;
    }

    /// @inheritdoc IERC20VaultGovernance
    function commitDelayedStrategyParams(uint256 nft) external {
        _commitDelayedStrategyParams(nft, msg.sender);
        emit CommitDelayedStrategyParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams))
        );
    }
}
