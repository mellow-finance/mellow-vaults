// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/validators/IValidator.sol";

contract ApproveValidator is IValidator {
    uint256 public constant exactInputSingleSelector = uint32(ISwapRouter.exactInputSingle.selector);
    uint256 public constant exactInput = uint32(ISwapRouter.exactInput.selector);
    uint256 public constant exactOutputSingleSelector = uint32(ISwapRouter.exactOutputSingle.selector);
    uint256 public constant exactOutput = uint32(ISwapRouter.exactOutput.selector);
    address public immutable swapRouter;

    constructor(address swapRouter_) {
        swapRouter = swapRouter_;
    }

    // @inhericdoc IValidator
    function validate(
        address addr,
        uint256 value,
        bytes calldata data
    ) external view returns (uint256) {
        uint256 selector;
        assembly {
            selector := calldataload(0)
            selector := shr(selector, 224)
        }
    }
}
