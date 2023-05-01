// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract ERC20Validator is ContractMeta, Validator {
    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address sender,
        address addr,
        uint256 value,
        bytes4 selector,
        bytes calldata data
    ) external view {
        require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        if (selector == APPROVE_SELECTOR) {
            address spender;
            assembly {
                spender := calldataload(data.offset)
            }
            _verifyApprove(sender, addr, spender);
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("ERC20Validator");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _verifyApprove(
        address sender,
        address token,
        address spender
    ) private view {
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        if (!protocolGovernance.hasPermission(token, PermissionIdsLibrary.ERC20_TRANSFER)) {
            revert(ExceptionsLibrary.FORBIDDEN);
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
