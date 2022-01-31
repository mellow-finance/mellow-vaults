// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IProtocolGovernance.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract AllowAllValidator is ContractMeta, Validator {
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

    function CONTRACT_NAME_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_NAME));
    }

    function CONTRACT_VERSION_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_VERSION));
    }
}
