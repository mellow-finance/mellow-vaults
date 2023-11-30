// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";

import "./DepositWrapper.sol";
import "./StakingDepositWrapper.sol";

import "../libraries/external/FullMath.sol";

contract OmniDepositWrapper {
    error ExecutionError();

    using SafeERC20 for IERC20;

    struct Data {
        address from;
        address to;
        address tokenIn;
        address router;
        address rootVault;
        address wrapper;
        address farm;
        uint256 amountIn;
        uint256 minLpAmount;
        bytes vaultOptions;
        uint256[] minReminders;
        bytes[] callbacks;
    }

    uint256 public constant Q96 = 2**96;

    address public immutable uniswapV3Router;
    IUniswapV3Factory public immutable uniswapV3Factory;

    constructor(address uniswapV3Router_, IUniswapV3Factory uniswapV3Factory_) {
        uniswapV3Router = uniswapV3Router_;
        uniswapV3Factory = uniswapV3Factory_;
    }

    function getOffchainData(Data memory d, uint256[] memory pricesX96) public view returns (Data memory) {
        address[] memory tokens = IERC20RootVault(d.rootVault).vaultTokens();
        uint256[] memory swapAmounts;
        (swapAmounts, d.minLpAmount) = calculateSwapAmounts(d.rootVault, d.tokenIn, d.amountIn, pricesX96);
        d.callbacks = new bytes[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            d.callbacks[i] = abi.encodePacked(swapAmounts[i]);
        }
        d.router = uniswapV3Router;
        return d;
    }

    function getUniswapData(Data memory d) public view returns (Data memory) {
        address[] memory tokens = IERC20RootVault(d.rootVault).vaultTokens();
        ISwapRouter.ExactInputSingleParams[] memory swapParams = new ISwapRouter.ExactInputSingleParams[](
            tokens.length
        );
        uint256[] memory pricesX96 = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            (swapParams[i], pricesX96[i]) = getUniswapCallback(d.tokenIn, tokens[i]);
        }
        uint256[] memory swapAmounts;
        (swapAmounts, d.minLpAmount) = calculateSwapAmounts(d.rootVault, d.tokenIn, d.amountIn, pricesX96);
        bytes[] memory callbacks = new bytes[](tokens.length);
        uint256 index = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (swapAmounts[i] == 0) continue;
            swapParams[i].amountIn = swapAmounts[i];
            callbacks[index++] = abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, swapParams[i]);
        }

        assembly {
            mstore(callbacks, index)
        }
        d.callbacks = callbacks;
        d.router = uniswapV3Router;
        return d;
    }

    function getUniswapCallback(address tokenIn, address tokenOut)
        public
        view
        returns (ISwapRouter.ExactInputSingleParams memory, uint256)
    {
        if (tokenIn == tokenOut) {
            return (
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: 0,
                    fee: 0,
                    deadline: type(uint256).max,
                    sqrtPriceLimitX96: 0,
                    amountOutMinimum: 0,
                    recipient: address(this)
                }),
                Q96
            );
        }
        uint24[4] memory feeTiers = [uint24(100), 500, 3000, 10000];
        uint256 optimalAmount = 0;
        uint24 optimalFeeTier = 0;
        address optimalPool;
        for (uint256 i = 0; i < feeTiers.length; i++) {
            address pool = uniswapV3Factory.getPool(tokenIn, tokenOut, feeTiers[i]);
            if (pool == address(0)) continue;
            uint256 poolAmount = IERC20(tokenOut).balanceOf(pool);
            if (poolAmount > optimalAmount) {
                optimalAmount = poolAmount;
                optimalFeeTier = feeTiers[i];
                optimalPool = pool;
            }
        }
        if (optimalFeeTier == 0) revert("Address zero");
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(optimalPool).slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (tokenIn == IUniswapV3Pool(optimalPool).token0()) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }
        return (
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: 0,
                fee: optimalFeeTier,
                deadline: type(uint256).max,
                sqrtPriceLimitX96: 0,
                amountOutMinimum: 0,
                recipient: address(this)
            }),
            priceX96
        );
    }

    function calculateSwapAmounts(
        address rootVault,
        address tokenIn,
        uint256 amountIn,
        uint256[] memory pricesX96
    ) public view returns (uint256[] memory swapAmounts, uint256 expectedLpAmount) {
        (, uint256[] memory tvl) = IERC20RootVault(rootVault).tvl();
        uint256 capitalInTokenIn = 0;
        for (uint256 i = 0; i < pricesX96.length; i++) {
            capitalInTokenIn += FullMath.mulDiv(tvl[i], pricesX96[i], Q96);
        }
        expectedLpAmount = FullMath.mulDiv(IERC20(rootVault).totalSupply(), amountIn, capitalInTokenIn);
        address[] memory tokens = IERC20RootVault(rootVault).vaultTokens();
        swapAmounts = new uint256[](tokens.length);
        uint256 cumulativeValue = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenIn) continue;
            uint256 ratioX96 = FullMath.mulDiv(tvl[i], pricesX96[i], capitalInTokenIn);
            swapAmounts[i] = FullMath.mulDiv(amountIn, ratioX96, Q96);
            if (cumulativeValue + swapAmounts[i] > amountIn) {
                swapAmounts[i] -= cumulativeValue + swapAmounts[i] - amountIn;
            }
            cumulativeValue += swapAmounts[i];
        }
    }

    function deposit(Data memory d) external returns (uint256 lpAmount, uint256[] memory returnedAmounts) {
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
        returnedAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (d.minReminders.length != 0 && d.minReminders[i] >= balance) continue;
            IERC20(tokens[i]).safeTransfer(d.to, balance);
            returnedAmounts[i] = balance;
        }
    }
}
