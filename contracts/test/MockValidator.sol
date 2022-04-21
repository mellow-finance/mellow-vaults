// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/vaults/IVault.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../validators/Validator.sol";

contract MockValidator is Validator {
    constructor(IProtocolGovernance protocolGovernance_) BaseValidator(protocolGovernance_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address,
        address addr,
        uint256 value,
        bytes4 selector,
        bytes calldata data
    ) external view {}

    // -------------------  INTERNAL, VIEW  -------------------

    function _verifyMultiCall(
        IVault vault,
        address recipient,
        bytes memory path
    ) private view {}

    function _verifySingleCall(
        IVault,
        address,
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) private view {}

    function _verifyPathItem(
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) private view {}
}
