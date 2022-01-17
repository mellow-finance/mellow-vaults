// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

interface IContractMeta {
    function CONRTACT_NAME() external view returns (bytes32);
    function CONTRACT_VERSION() external view returns (uint256);
}
