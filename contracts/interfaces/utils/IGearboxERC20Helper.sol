// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IGearboxERC20Helper {
    function calcTvl(address[] memory _vaultTokens) external view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts);
}
