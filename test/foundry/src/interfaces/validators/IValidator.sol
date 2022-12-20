// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./IBaseValidator.sol";

interface IValidator is IBaseValidator, IERC165 {
    // @notice Validate if call can be made to external contract.
    // @dev Reverts if validation failed. Returns nothing if validation is ok
    // @param sender Sender of the externalCall method
    // @param addr Address of the called contract
    // @param value Ether value for the call
    // @param selector Selector of the called method
    // @param data Call data after selector
    function validate(
        address sender,
        address addr,
        uint256 value,
        bytes4 selector,
        bytes calldata data
    ) external view;
}
