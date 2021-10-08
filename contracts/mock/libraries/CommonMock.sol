// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../../libraries/Common.sol";

contract CommonMock {
    constructor() {

    }

    function bubbleSort(address[] memory arr) external pure returns(address[] memory) {
        Common.bubbleSort(arr);
        return arr;
    }

    function isSortedAndUnique(address[] memory tokens) external pure returns (bool) {
        return Common.isSortedAndUnique(tokens);
    }

    /// todo: projectTokenAmounts

    /// todo: splitAmounts

    /// todo: _isSubsetOf
}
