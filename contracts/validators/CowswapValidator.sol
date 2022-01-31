// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract CowswapValidator is ContractMeta, Validator {
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
        // we don't validate TRUSTED_STRATEGY here because it's validated at allowance level
        if (selector == PRE_SIGNATURE_SELECTOR) {
            return;
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function CONTRACT_NAME() internal pure override returns (bytes32) {
        return bytes32("CowswapValidator");
    }

    function CONTRACT_VERSION() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
