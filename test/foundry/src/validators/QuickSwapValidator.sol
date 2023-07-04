// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/quickswap/IAlgebraSwapRouter.sol";
import "../interfaces/external/quickswap/IAlgebraFactory.sol";
import "../interfaces/vaults/IVault.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract QuickSwapValidator is ContractMeta, Validator {
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = IAlgebraSwapRouter.exactInputSingle.selector;
    bytes4 public constant EXACT_INPUT_SELECTOR = IAlgebraSwapRouter.exactInput.selector;
    bytes4 public constant EXACT_OUTPUT_SINGLE_SELECTOR = IAlgebraSwapRouter.exactOutputSingle.selector;
    bytes4 public constant EXACT_OUTPUT_SELECTOR = IAlgebraSwapRouter.exactOutput.selector;
    address public immutable swapRouter;
    IAlgebraFactory public immutable factory;

    constructor(
        IProtocolGovernance protocolGovernance_,
        address swapRouter_,
        IAlgebraFactory factory_
    ) BaseValidator(protocolGovernance_) {
        swapRouter = swapRouter_;
        factory = factory_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    // @inhericdoc IValidator
    function validate(address, address addr, uint256 value, bytes4 selector, bytes calldata data) external view {
        require(swapRouter == addr, ExceptionsLibrary.INVALID_TARGET);
        require(value == 0, ExceptionsLibrary.INVALID_VALUE);
        IVault vault = IVault(msg.sender);
        if (selector == EXACT_INPUT_SINGLE_SELECTOR) {
            IAlgebraSwapRouter.ExactInputSingleParams memory params = abi.decode(
                data,
                (IAlgebraSwapRouter.ExactInputSingleParams)
            );
            _verifySingleCall(vault, params.recipient, params.tokenIn, params.tokenOut);
        } else if (selector == EXACT_OUTPUT_SINGLE_SELECTOR) {
            IAlgebraSwapRouter.ExactOutputSingleParams memory params = abi.decode(
                data,
                (IAlgebraSwapRouter.ExactOutputSingleParams)
            );
            _verifySingleCall(vault, params.recipient, params.tokenIn, params.tokenOut);
        } else if (selector == EXACT_INPUT_SELECTOR) {
            IAlgebraSwapRouter.ExactInputParams memory params = abi.decode(data, (IAlgebraSwapRouter.ExactInputParams));
            _verifyMultiCall(vault, params.recipient, params.path);
        } else if (selector == EXACT_OUTPUT_SELECTOR) {
            IAlgebraSwapRouter.ExactOutputParams memory params = abi.decode(
                data,
                (IAlgebraSwapRouter.ExactOutputParams)
            );
            _verifyMultiCall(vault, params.recipient, params.path);
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("QuickSwapValidator");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _verifyMultiCall(IVault vault, address recipient, bytes memory path) private view {
        uint256 i;
        address token0;
        address token1;
        uint256 tokenMask = (1 << 160) - 1;
        require(recipient == address(vault), ExceptionsLibrary.INVALID_TARGET);
        // the sample QuickSwap path structure is (DAI address, USDC address, WETH address)
        // addresses are 20 bytes
        require((path.length % 20 == 0) && (path.length >= 40), ExceptionsLibrary.INVALID_LENGTH);
        while (path.length - i > 20) {
            assembly {
                let o := add(add(path, 0x20), i)
                let d := mload(o)
                token0 := shr(96, d)
                d := mload(add(o, 8))
                token1 := and(d, tokenMask)
            }
            _verifyPathItem(token0, token1);
            i += 20;
        }
        require(vault.isVaultToken(token1), ExceptionsLibrary.INVALID_TOKEN);
    }

    function _verifySingleCall(IVault vault, address recipient, address tokenIn, address tokenOut) private view {
        require(recipient == address(vault), ExceptionsLibrary.INVALID_TARGET);
        require(vault.isVaultToken(tokenOut), ExceptionsLibrary.INVALID_TOKEN);
        _verifyPathItem(tokenIn, tokenOut);
    }

    function _verifyPathItem(address tokenIn, address tokenOut) private view {
        require(tokenIn != tokenOut, ExceptionsLibrary.INVALID_TOKEN);
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        address pool = factory.poolByPair(tokenIn, tokenOut);
        require(
            protocolGovernance.hasPermission(pool, PermissionIdsLibrary.ERC20_APPROVE),
            ExceptionsLibrary.FORBIDDEN
        );
    }
}
