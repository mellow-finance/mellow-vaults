// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "../libraries/ExceptionsLibrary.sol";

contract BatchCall {
    function batchcall(address[] calldata targets, bytes[] calldata data) external returns (bytes[] memory results) {
        require(targets.length == data.length, ExceptionsLibrary.INVALID_LENGTH);
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(targets[i], data[i]);
        }
        return results;
    }
}
