// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "./Validator.sol";

contract CowswapValidator is IContractMeta, Validator {
    bytes32 public constant CONTRACT_NAME = "CowswapValidator";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    bytes4 public constant PRE_SIGNATURE_SELECTOR = 0xec6cb13f;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
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
