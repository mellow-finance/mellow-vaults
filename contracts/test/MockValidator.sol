// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/validators/IValidator.sol";
import "../validators/Validator.sol";

contract MockValidator is Validator {
    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // @inhericdoc IValidator
    function validate(
        address sender,
        address addr,
        uint256 value,
        bytes4 selector,
        bytes calldata data
    ) external view {
        return;
    }
}
