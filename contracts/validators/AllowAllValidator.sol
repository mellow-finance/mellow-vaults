// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/utils/IContractMeta.sol";
import "./Validator.sol";

contract AllowAllValidator is IContractMeta, Validator {
    bytes32 public constant CONTRACT_NAME = "AllowAllValidator";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address,
        uint256,
        bytes calldata
    ) external view {}
}
