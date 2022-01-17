// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

interface IContractRegistry {
    function registerContracts(address[] calldata targets) external;
}
