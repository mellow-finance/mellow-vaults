// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract AllowAllValidator is ContractMeta, Validator {
    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inheritdoc IValidator
    function validate(
        address,
        address,
        uint256,
        bytes4,
        bytes calldata
    ) external view {}

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("AllowAllValidator");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
