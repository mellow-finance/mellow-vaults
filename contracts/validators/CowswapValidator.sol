// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./Validator.sol";

contract CowswapValidator is Validator {
    bytes4 public constant PRE_SIGNATURE_SELECTOR = 0xec6cb13f;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address,
        uint256,
        bytes calldata data
    ) external pure {
        bytes4 selector = CommonLibrary.getSelector(data);
        if (selector == PRE_SIGNATURE_SELECTOR) {
            return;
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }
}
