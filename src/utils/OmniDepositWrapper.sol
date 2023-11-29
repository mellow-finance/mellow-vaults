// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";

import "./DepositWrapper.sol";
import "./StakingDepositWrapper.sol";
import "./DefaultAccessControl.sol";

import "../libraries/external/FullMath.sol";

contract OmniDepositWrapper is DefaultAccessControl {
    error ExecutionError();

    using SafeERC20 for IERC20;

    struct Data {
        address from;
        address to;
        address tokenIn;
        uint256 amountIn;
        uint256 minLpAmount;
        address router;
        bytes vaultOptions;
        bytes[] callbacks;
        address rootVault;
        address wrapper;
        address farm;
    }

    uint256 public constant Q96 = 2**96;

    address public immutable uniswapV3Router;
    IUniswapV3Factory public immutable uniswapV3Factory;

    constructor(
        address admin,
        address uniswapV3Router_,
        IUniswapV3Factory uniswapV3Factory_
    ) DefaultAccessControl(admin) {
        uniswapV3Router = uniswapV3Router_;
        uniswapV3Factory = uniswapV3Factory_;
    }

    function getUniswapCallback(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view returns (address, bytes memory) {
        uint24[4] memory feeTiers = [uint24(100), 500, 3000, 10000];
        uint256 optimalAmount = 0;
        uint24 optimalFeeTier = 0;
        for (uint256 i = 0; i < feeTiers.length; i++) {
            address pool = uniswapV3Factory.getPool(tokenIn, tokenOut, feeTiers[i]);
            if (pool == address(0)) continue;
            uint256 poolAmount = IERC20(tokenOut).balanceOf(pool);
            if (poolAmount > optimalAmount) {
                optimalAmount = poolAmount;
                optimalFeeTier = feeTiers[i];
            }
        }
        if (optimalFeeTier == 0) return (address(0), "");
        return (
            uniswapV3Router,
            abi.encodeWithSelector(
                ISwapRouter.exactInputSingle.selector,
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    fee: optimalFeeTier,
                    deadline: type(uint256).max,
                    sqrtPriceLimitX96: 0,
                    amountOutMinimum: 0,
                    recipient: address(this)
                })
            )
        );
    }

    function calculateSwapAmounts(
        address rootVault,
        uint256 amountIn,
        uint256[] memory pricesX96
    )
        public
        view
        returns (
            address[] memory tokens,
            uint256[] memory swapAmounts,
            uint256 expectedLpAmount
        )
    {
        (, uint256[] memory tvl) = IERC20RootVault(rootVault).tvl();
        uint256 capitalInTokenIn = 0;
        for (uint256 i = 0; i < pricesX96.length; i++) {
            capitalInTokenIn += FullMath.mulDiv(tvl[i], pricesX96[i], Q96);
        }
        expectedLpAmount = FullMath.mulDiv(IERC20(rootVault).totalSupply(), amountIn, capitalInTokenIn);
        tokens = IERC20RootVault(rootVault).vaultTokens();
        swapAmounts = new uint256[](tokens.length);
        uint256 cumulativeValue = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 ratioX96 = FullMath.mulDiv(tvl[i], pricesX96[i], capitalInTokenIn);
            swapAmounts[i] = FullMath.mulDiv(amountIn, ratioX96, Q96);
            if (cumulativeValue + swapAmounts[i] > amountIn) {
                swapAmounts[i] -= cumulativeValue + swapAmounts[i] - amountIn;
            }
            cumulativeValue += swapAmounts[i];
        }
    }

    function deposit(Data memory d) external returns (uint256 lpAmount) {
        IERC20(d.tokenIn).safeTransferFrom(d.from, address(this), d.amountIn);
        IERC20(d.tokenIn).safeApprove(d.router, type(uint256).max);
        for (uint256 i = 0; i < d.callbacks.length; i++) {
            (bool success, ) = d.router.call(d.callbacks[i]);
            if (!success) revert ExecutionError();
        }
        IERC20(d.tokenIn).safeApprove(d.router, 0);
        address[] memory tokens = IERC20RootVault(d.rootVault).vaultTokens();
        uint256[] memory amounts = new uint256[](tokens.length);
        address to = d.rootVault;
        if (d.wrapper != address(0)) to = d.wrapper;
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).safeApprove(to, type(uint256).max);
        }

        if (d.farm == address(0) && d.wrapper == address(0)) {
            IERC20RootVault(d.rootVault).deposit(amounts, d.minLpAmount, d.vaultOptions);
        } else if (d.farm == address(0) && d.wrapper != address(0)) {
            DepositWrapper(d.wrapper).deposit(IERC20RootVault(d.rootVault), amounts, d.minLpAmount, d.vaultOptions);
        } else {
            StakingDepositWrapper(d.wrapper).deposit(
                IERC20RootVault(d.rootVault),
                InstantFarm(d.farm),
                amounts,
                d.minLpAmount,
                d.vaultOptions
            );
        }
        lpAmount = IERC20(d.rootVault).balanceOf(address(this));
        IERC20(d.rootVault).safeTransfer(d.to, lpAmount);
    }

    function claim(address[] memory tokens) external {
        _requireAtLeastOperator();
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }
}
