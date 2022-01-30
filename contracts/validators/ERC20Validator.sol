// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "./Validator.sol";

contract ERC20Validator is IContractMeta, Validator {
    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector;
    bytes32 public constant CONTRACT_NAME = "ERC20Validator";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";
    bytes4 public constant EXCHANGE_SELECTOR = 0x3df02124;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address sender,
        address addr,
        uint256 value,
        bytes calldata data
    ) external view {
        require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        bytes4 selector = CommonLibrary.getSelector(data);
        if (selector == APPROVE_SELECTOR) {
            address spender;
            assembly {
                spender := calldataload(add(data.offset, 4))
                spender := shr(96, addr)
            }
            _verifyApprove(sender, addr, spender);
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _verifyApprove(
        address sender,
        address token,
        address spender
    ) private view {
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        if (protocolGovernance.hasPermission(token, PermissionIdsLibrary.ERC20_TRANSFER)) {
            return;
        }
        if (protocolGovernance.hasPermission(spender, PermissionIdsLibrary.ERC20_APPROVE)) {
            return;
        }
        if (
            protocolGovernance.hasPermission(spender, PermissionIdsLibrary.ERC20_APPROVE_RESTRICTED) &&
            protocolGovernance.hasPermission(sender, PermissionIdsLibrary.TRUSTED_STRATEGY)
        ) {
            return;
        }
        revert(ExceptionsLibrary.FORBIDDEN);
    }
}
