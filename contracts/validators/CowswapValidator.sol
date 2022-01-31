// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract CowswapValidator is ContractMeta, Validator {
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

    function CONTRACT_NAME_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_NAME));
    }

    function CONTRACT_VERSION_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_VERSION));
    }
}
