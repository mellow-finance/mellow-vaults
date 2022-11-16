// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/vaults/IVault.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract UniV3Validator is ContractMeta, Validator {
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    bytes4 public constant EXACT_INPUT_SELECTOR = ISwapRouter.exactInput.selector;
    bytes4 public constant EXACT_OUTPUT_SINGLE_SELECTOR = ISwapRouter.exactOutputSingle.selector;
    bytes4 public constant EXACT_OUTPUT_SELECTOR = ISwapRouter.exactOutput.selector;
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
        address,
        address addr,
        uint256 value,
        bytes4 selector,
        bytes calldata data
    ) external view {
        require(address(swapRouter) == addr, ExceptionsLibrary.INVALID_TARGET);
        require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        IVault vault = IVault(msg.sender);
        if (selector == EXACT_INPUT_SINGLE_SELECTOR) {
            ISwapRouter.ExactInputSingleParams memory params = abi.decode(data, (ISwapRouter.ExactInputSingleParams));
            _verifySingleCall(vault, params.recipient, params.tokenIn, params.tokenOut, params.fee);
        } else if (selector == EXACT_OUTPUT_SINGLE_SELECTOR) {
            ISwapRouter.ExactOutputSingleParams memory params = abi.decode(data, (ISwapRouter.ExactOutputSingleParams));
            _verifySingleCall(vault, params.recipient, params.tokenIn, params.tokenOut, params.fee);
        } else if (selector == EXACT_INPUT_SELECTOR) {
            ISwapRouter.ExactInputParams memory params = abi.decode(data, (ISwapRouter.ExactInputParams));
            _verifyMultiCall(vault, params.recipient, params.path);
        } else if (selector == EXACT_OUTPUT_SELECTOR) {
            ISwapRouter.ExactOutputParams memory params = abi.decode(data, (ISwapRouter.ExactOutputParams));
            _verifyMultiCall(vault, params.recipient, params.path);
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("UniV3Validator");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _verifyMultiCall(
        IVault vault,
        address recipient,
        bytes memory path
    ) private view {
        uint256 i;
        address token0;
        address token1;
        uint24 fee;
        uint256 feeMask = (1 << 24) - 1;
        uint256 tokenMask = (1 << 160) - 1;
        require(recipient == address(vault), ExceptionsLibrary.INVALID_TARGET);
        // the sample UniV3 path structure is (DAI address,DAI-USDC fee, USDC, USDC-WETH fee, WETH)
        // addresses are 20 bytes, fees are 3 bytes
        require(((path.length + 3) % 23 == 0) && (path.length >= 43), ExceptionsLibrary.INVALID_LENGTH);
        while (path.length - i > 20) {
            assembly {
                let o := add(add(path, 0x20), i)
                let d := mload(o)
                d := shr(72, d)
                fee := and(d, feeMask)
                token0 := shr(24, d)
                d := mload(add(o, 11))
                token1 := and(d, tokenMask)
            }
            _verifyPathItem(token0, token1, fee);
            i += 23;
        }
        require(vault.isVaultToken(token1), ExceptionsLibrary.INVALID_TOKEN);
    }

    function _verifySingleCall(
        IVault vault,
        address recipient,
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) private view {
        require(recipient == address(vault), ExceptionsLibrary.INVALID_TARGET);
        require(vault.isVaultToken(tokenOut), ExceptionsLibrary.INVALID_TOKEN);
        _verifyPathItem(tokenIn, tokenOut, fee);
    }

    function _verifyPathItem(
        address tokenIn,
        address tokenOut,
        uint24 fee
    ) private view {
        require(tokenIn != tokenOut, ExceptionsLibrary.INVALID_TOKEN);
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        address pool = factory.getPool(tokenIn, tokenOut, fee);
        require(
            protocolGovernance.hasPermission(pool, PermissionIdsLibrary.ERC20_APPROVE),
            ExceptionsLibrary.FORBIDDEN
        );
    }
}
