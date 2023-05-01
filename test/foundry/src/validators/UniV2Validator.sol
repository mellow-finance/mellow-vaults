// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/univ2/IUniswapV2Factory.sol";
import "../interfaces/external/univ2/IUniswapV2Router01.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/vaults/IVault.sol";
import "../libraries/PermissionIdsLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./Validator.sol";

contract UniV2Validator is ContractMeta, Validator {
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
        bytes4 selector,
        bytes calldata data
    ) external view {
        require(address(swapRouter) == addr, ExceptionsLibrary.INVALID_TARGET);
        IVault vault = IVault(msg.sender);

        address[] memory path;
        address to;

        if ((selector == EXACT_ETH_INPUT_SELECTOR) || (selector == EXACT_TOKENS_OUTPUT_SELECTOR)) {
            (, path, to, ) = abi.decode(data, (uint256, address[], address, uint256));
        } else if (
            (selector == EXACT_ETH_OUTPUT_SELECTOR) ||
            (selector == EXACT_TOKENS_INPUT_SELECTOR) ||
            (selector == EXACT_INPUT_SELECTOR) ||
            (selector == EXACT_OUTPUT_SELECTOR)
        ) {
            require(value == 0, ExceptionsLibrary.INVALID_VALUE);
            (, , path, to, ) = abi.decode(data, (uint256, uint256, address[], address, uint256));
        } else {
            revert(ExceptionsLibrary.INVALID_SELECTOR);
        }

        require(to == msg.sender);
        _verifyPath(vault, path);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("UniV2Validator");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _verifyPath(IVault vault, address[] memory path) private view {
        require(path.length > 1, ExceptionsLibrary.INVALID_LENGTH);
        require(vault.isVaultToken(path[path.length - 1]), ExceptionsLibrary.INVALID_TOKEN);
        IProtocolGovernance protocolGovernance = _validatorParams.protocolGovernance;
        for (uint256 i = 0; i < path.length - 1; i++) {
            address token0 = path[i];
            address token1 = path[i + 1];
            require(token0 != token1, ExceptionsLibrary.INVALID_TOKEN);
            address pool = factory.getPair(token0, token1);
            require(
                protocolGovernance.hasPermission(pool, PermissionIdsLibrary.ERC20_APPROVE),
                ExceptionsLibrary.FORBIDDEN
            );
        }
    }
}
