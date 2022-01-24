// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/external/univ2/IUniswapV2Factory.sol";
import "../interfaces/external/univ2/IUniswapV2Router01.sol";
import "../interfaces/validators/IValidator.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./Validator.sol";

contract UniV2Validator is Validator {
    struct TokenInput {
        uint256 amount;
        uint256 amountMax;
        address[] path;
        address to;
        uint256 deadline;
    }
    struct EthInput {
        uint256 amountMax;
        address[] path;
        address to;
        uint256 deadline;
    }
    using EnumerableSet for EnumerableSet.AddressSet;
    bytes4 public constant EXACT_INPUT_SELECTOR = IUniswapV2Router01.swapExactTokensForTokens.selector;
    bytes4 public constant EXACT_OUTPUT_SELECTOR = IUniswapV2Router01.swapTokensForExactTokens.selector;
    bytes4 public constant EXACT_ETH_INPUT_SELECTOR = IUniswapV2Router01.swapExactETHForTokens.selector;
    bytes4 public constant EXACT_ETH_OUTPUT_SELECTOR = IUniswapV2Router01.swapTokensForExactETH.selector;
    bytes4 public constant EXACT_TOKENS_INPUT_SELECTOR = IUniswapV2Router01.swapExactTokensForETH.selector;
    bytes4 public constant EXACT_TOKENS_OUTPUT_SELECTOR = IUniswapV2Router01.swapETHForExactTokens.selector;

    address public immutable swapRouter;
    IUniswapV2Factory public immutable factory;

    constructor(
        IProtocolGovernance protocolGovernance_,
        address swapRouter_,
        IUniswapV2Factory factory_
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
        bytes calldata data
    ) external view {
        require(address(swapRouter) == addr, ExceptionsLibrary.INVALID_TARGET);
        bytes4 selector = CommonLibrary.getSelector(data);
        if ((selector == EXACT_ETH_INPUT_SELECTOR) || (selector == EXACT_TOKENS_OUTPUT_SELECTOR)) {
            (, address[] memory path, , ) = abi.decode(data, (uint256, address[], address, uint256));
            _verifyPath(path);
        } else if (
            (selector == EXACT_ETH_OUTPUT_SELECTOR) ||
            (selector == EXACT_TOKENS_INPUT_SELECTOR) ||
            (selector == EXACT_INPUT_SELECTOR) ||
            (selector == EXACT_OUTPUT_SELECTOR)
        ) {
            require(value == 0, ExceptionsLibrary.INVALID_VALUE);
            (, , address[] memory path, , ) = abi.decode(data, (uint256, uint256, address[], address, uint256));
            _verifyPath(path);
            return;
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _verifyPath(address[] memory path) private view {
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address token0 = path[i];
            address token1 = path[i + 1];
            address pool = factory.getPair(token0, token1);
            require(token0 != token1, ExceptionsLibrary.INVALID_TOKEN);
            require(
                protocolGovernance.hasPermission(pool, PermissionIdsLibrary.ERC20_APPROVE),
                ExceptionsLibrary.FORBIDDEN
            );
        }
    }
}
