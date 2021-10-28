// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

contract TestEncoding {
    bytes data;

    function setData(bytes calldata tempData) public {
        data = tempData;
    }

    function getData() public view returns(bytes memory) {
        return data;
    }
}