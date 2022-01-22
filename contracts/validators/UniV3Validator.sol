// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
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
    ) external view {
        require(address(swapRouter) != addr, ExceptionsLibrary.INVALID_TARGET);
        require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        uint256 selector = CommonLibrary.getSelector(data);
        if (selector == exactInputSingleSelector) {
            ISwapRouter.ExactInputSingleParams memory params = abi.decode(data, (ISwapRouter.ExactInputSingleParams));
            _verifySingleCall(params.tokenIn, params.tokenOut, params.fee);
            return;
        }
        if (selector == exactOutputSingleSelector) {
            ISwapRouter.ExactOutputSingleParams memory params = abi.decode(data, (ISwapRouter.ExactOutputSingleParams));
            _verifySingleCall(params.tokenIn, params.tokenOut, params.fee);
            return;
        }
        if (selector == exactInputSelector) {
            ISwapRouter.ExactInputParams memory params = abi.decode(data, (ISwapRouter.ExactInputParams));
            _verifyMultiCall(params.path);
            return;
        }
        if (selector == exactOutputSelector) {
            ISwapRouter.ExactOutputParams memory params = abi.decode(data, (ISwapRouter.ExactOutputParams));
            _verifyMultiCall(params.path);
            return;
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _verifyMultiCall(bytes memory path) private view {
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
            _verifySingleCall(token0, token1, fee);
            i += 23;
        }
    }

    function _verifySingleCall(
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) private view {
        require(tokenIn != tokenOut, ExceptionsLibrary.INVALID_TOKEN);
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        address pool = factory.getPool(tokenIn, tokenOut, fee);
        require(protocolGovernance.hasPermission(pool, PermissionIdsLibrary.SWAP), ExceptionsLibrary.FORBIDDEN);
    }
}
