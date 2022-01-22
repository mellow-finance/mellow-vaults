// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "./BaseValidator.sol";

contract UniV3Validator is IValidator, BaseValidator {
    using EnumerableSet for EnumerableSet.AddressSet;
    uint256 public constant exactInputSingleSelector = uint32(ISwapRouter.exactInputSingle.selector);
    uint256 public constant exactInputSelector = uint32(ISwapRouter.exactInput.selector);
    uint256 public constant exactOutputSingleSelector = uint32(ISwapRouter.exactOutputSingle.selector);
    uint256 public constant exactOutputSelector = uint32(ISwapRouter.exactOutput.selector);
    address public immutable swapRouter;
    IUniswapV3Factory public immutable factory;

    constructor(
        IProtocolGovernance protocolGovernance_,
        address swapRouter_,
        IUniswapV3Factory factory_
    ) BaseValidator(protocolGovernance_) {
        swapRouter = swapRouter_;
        factory = factory_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(
        address addr,
        uint256 value,
        bytes calldata data
    ) external view returns (uint256) {
        if (address(swapRouter) != addr) {
            return 1;
        }
        if (value > 0) {
            return 10;
        }
        uint256 selector = CommonLibrary.getSelector(data);
        if (selector == exactInputSingleSelector) {
            ISwapRouter.ExactInputSingleParams memory params = abi.decode(data, (ISwapRouter.ExactInputSingleParams));
            return _verifySingleCall(params.tokenIn, params.tokenOut, params.fee);
        }
        if (selector == exactOutputSingleSelector) {
            ISwapRouter.ExactOutputSingleParams memory params = abi.decode(data, (ISwapRouter.ExactOutputSingleParams));
            return _verifySingleCall(params.tokenIn, params.tokenOut, params.fee);
        }
        if (selector == exactInputSelector) {
            ISwapRouter.ExactInputParams memory params = abi.decode(data, (ISwapRouter.ExactInputParams));
            return _verifyMultiCall(params.path);
        }
        if (selector == exactOutputSelector) {
            ISwapRouter.ExactOutputParams memory params = abi.decode(data, (ISwapRouter.ExactOutputParams));
            return _verifyMultiCall(params.path);
        }

        return 2;
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _verifyMultiCall(bytes memory path) private view returns (uint256) {
        uint256 i;
        address token0;
        address token1;
        uint24 fee;
        uint256 feeMask = (1 << 24) - 1;
        while (path.length - i > 20) {
            // the sample UniV3 path structure is (DAI address,DAI-USDC fee, USDC, USDC-WETH fee, WETH)
            // addresses are 20 bytes, fees are 3 bytes
            assembly {
                let o := add(add(path, 0x20), i)
                let d := mload(o)
                d := shr(72, d)
                fee := and(d, feeMask)
                token0 := shr(24, d)
                d := mload(add(o, 23))
                token1 := shr(96, d)
            }
            uint256 res = _verifySingleCall(token0, token1, fee);
            if (res > 0) {
                return res;
            }
            i += 23;
        }
        return 0;
    }

    function _verifySingleCall(
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) private view returns (uint256) {
        if (tokenIn == tokenOut) {
            return 3;
        }
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        address pool = factory.getPool(tokenIn, tokenOut, fee);
        if (!protocolGovernance.hasPermission(pool, PermissionIdsLibrary.SWAP)) {
            return 13;
        }
        return 0;
    }
}
