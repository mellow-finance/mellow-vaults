// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../../libraries/Common.sol";

contract CommonTest {
    constructor() {

    }

    function bubbleSort(address[] memory arr) external pure returns(address[] memory) {
        Common.bubbleSort(arr);
        return arr;
    }

    function isSortedAndUnique(address[] memory tokens) external pure returns (bool) {
        return Common.isSortedAndUnique(tokens);
    }

    function projectTokenAmountTest(
        address[] memory tokens,
        address[] memory tokensToProject,
        uint256[] memory tokenAmountsToProject
    ) external pure returns (uint256[] memory) {
        return Common.projectTokenAmounts(tokens, tokensToProject, tokenAmountsToProject);
    }

    function splitAmountsTest(
        uint256[] memory amounts,
        uint256[][] memory weights
    ) external pure returns (uint256[] memory) {
        return Common.splitAmounts(amounts, weights);
    }

    function isContractTest(address addr) external view returns (bool) {
        return Common.isContract(addr);
    }

    function isSubsetOfTest(
        address[] memory tokens,
        address[] memory tokensToCheck,
        address[] memory amountsToCheck
    ) external {
        Common._isSubsetOf(tokens, tokensToCheck, amountsToCheck);
    }
}
