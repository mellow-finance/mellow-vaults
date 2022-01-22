// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IValidator {
    // @notice Validate if call can be made to external contract.
    // @param addr Address of the called contract
    // @param value Ether value for the call
    // @param data Call data
    // @return 0 if validated successfully, errorCode > 0 otherwise
    function validate(
        address addr,
        uint256 value,
        bytes calldata data
    ) external view returns (uint256);
}
