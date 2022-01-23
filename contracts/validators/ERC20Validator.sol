// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "./Validator.sol";

contract ERC20Validator is Validator {
    uint256 public constant approveSelector = uint32(IERC20.approve.selector);

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address addr,
        uint256 value,
        bytes calldata data
    ) external view {
        require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        uint256 selector = CommonLibrary.getSelector(data);
        if (selector == approveSelector) {
            address spender;
            assembly {
                spender := calldataload(add(data.offset, 4))
                spender := shr(96, addr)
            }
            _verifyApprove(addr, spender);
        }
        revert(ExceptionsLibrary.INVALID_SELECTOR);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _verifyApprove(address token, address spender) private view {
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        require(protocolGovernance.hasPermission(token, PermissionIdsLibrary.ERC20_TRANSFER));
        require(protocolGovernance.hasPermission(spender, PermissionIdsLibrary.ERC20_APPROVE));
    }
}
