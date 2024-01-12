// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../vaults/ERC20RootVault.sol";

contract VeloViewHelper {
    struct Info {
        address vault;
        address farm;
        uint256 vaultFee;
        bool status;
        uint256 lpAmount;
        uint256 amountToken0;
        uint256 amountToken1;
        uint256 rewardAmount;
    }

    function registerMultiple(address[] memory vaults, address[] memory farms) public {}

    function getInfo(address pool, address user) public view returns (Info memory info) {}
}
