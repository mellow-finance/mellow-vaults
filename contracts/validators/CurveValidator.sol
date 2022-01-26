// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./Validator.sol";

contract CurveValidator is Validator {
    using EnumerableSet for EnumerableSet.AddressSet;
    bytes4 public constant EXCHANGE_SELECTOR = 0x3df02124;

    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address addr,
        uint256,
        bytes calldata data
    ) external view {
        bytes4 selector = CommonLibrary.getSelector(data);
        if (selector == EXCHANGE_SELECTOR) {
            (int128 i, int128 j, , ) = abi.decode(data, (int128, int128, uint256, uint256));
            require(i != j, ExceptionsLibrary.INVALID_VALUE);
            IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
            require(
                protocolGovernance.hasPermission(addr, PermissionIdsLibrary.ERC20_APPROVE),
                ExceptionsLibrary.FORBIDDEN
            );
            return;
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }
}
