// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "./BaseValidator.sol";

contract ApproveValidator is IValidator, BaseValidator {
    uint256 public constant approveSelector = uint32(IERC20.approve.selector);

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // @inhericdoc IValidator
    function validate(
        address addr,
        uint256 value,
        bytes calldata data
    ) external view returns (uint256) {
        uint256 selector = CommonLibrary.getSelector(data);
        assembly {
            selector := calldataload(0)
            selector := shr(selector, 224)
        }
    }
}
