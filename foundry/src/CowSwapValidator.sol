// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../test/helpers/IProtocolGovernance.sol";
import "../test/helpers/libraries/ExceptionsLibrary.sol";
import "./Validator.sol";

// @notice Validator allowing setPreSignature call with any params for cowswap
contract CowswapValidator is Validator {
    bytes4 public constant PRE_SIGNATURE_SELECTOR = 0xec6cb13f;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inheritdoc IValidator
    function validate(
        address,
        address,
        uint256,
        bytes4 selector,
        bytes calldata
    ) external pure {
        // we don't validate TRUSTED_STRATEGY here because it's validated at allowance level
        if (selector == PRE_SIGNATURE_SELECTOR) {
            return;
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }
}
