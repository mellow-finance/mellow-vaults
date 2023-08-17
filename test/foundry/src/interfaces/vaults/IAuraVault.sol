// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IIntegrationVault.sol";

import {IAggregatorV3} from "../external/chainlink/IAggregatorV3.sol";
import {IAsset} from "../external/balancer/vault/IVault.sol";

interface IAuraVault is IIntegrationVault {
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address pool_,
        address balancerVault_,
        address auraBooster_,
        address auraBaseRewardPool_
    ) external;

    function getPriceToUSDX96(IAggregatorV3 oracle, IAsset token) external view returns (uint256 priceX96);

    function claimRewards() external returns (uint256 amount);
}
