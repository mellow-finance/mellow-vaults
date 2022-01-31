// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract AllowAllValidator is ContractMeta, Validator {
    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address,
        uint256,
        bytes calldata
    ) external view {}

    // -------------------  INTERNAL, VIEW  -------------------

    function CONTRACT_NAME() internal pure override returns (bytes32) {
        return bytes32("AllowAllValidator");
    }

    function CONTRACT_VERSION() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
