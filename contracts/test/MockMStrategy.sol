// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../strategies/MStrategy.sol";

contract MockMStrategy is MStrategy {
    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_)
        MStrategy(positionManager_, router_)
    {}

    function targetTokenRatioD(
        int24 tick,
        int24 tickMin,
        int24 tickMax
    ) external pure returns (uint256) {
        return _targetTokenRatioD(tick, tickMin, tickMax);
    }

    function swapToTarget(SwapToTargetParams memory params, bytes memory vaultOptions) external {
        _swapToTarget(params, vaultOptions);
    }

    function rebalancePools(
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_,
        address[] memory tokens_,
        uint256[] memory minDeviations,
        bytes memory vaultOptions
    ) external returns (int256[] memory) {
        return _rebalancePools(erc20Vault_, moneyVault_, tokens_, minDeviations, vaultOptions);
    }
}
