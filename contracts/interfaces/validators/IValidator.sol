// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IBaseValidator.sol";

interface IValidator is IBaseValidator {
    // @notice Validate if call can be made to external contract.
    // @param addr Address of the called contract
    // @param value Ether value for the call
    // @param data Call data
    function validate(
        address addr,
        uint256 value,
        bytes calldata data
    ) external view;
}
