// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DepositWrapper.sol";

import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";

import "../interfaces/utils/IWrapperNativeToken.sol";

import "../libraries/external/FullMath.sol";

import "forge-std/src/Test.sol";

contract OneSidedDepositWrapper {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    uint256 public constant Q96 = 2**96;
    uint24[4] public fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    IUniswapV3Factory public immutable factory;
    ISwapRouter public immutable router;
    address public immutable wrapperNativeToken;

    constructor(
        address router_,
        address factory_,
        address wrapperNativeToken_
    ) {
        router = ISwapRouter(router_);
        factory = IUniswapV3Factory(factory_);
        wrapperNativeToken = wrapperNativeToken_;
    }

    function findBestPool(address tokenA, address tokenB)
        public
        view
        returns (address bestPool, uint256 priceX96OfBestPool)
    {
        uint24[4] memory fees_ = fees;
        uint256 bestAmount = 0;
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        for (uint24 i = 0; i < fees_.length; i++) {
            address pool = factory.getPool(tokenA, tokenB, fees_[i]);
            if (address(0) == pool) continue;
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
            uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
            uint256 amount0 = IERC20(tokenA).balanceOf(pool);
            uint256 amount1 = IERC20(tokenB).balanceOf(pool);
            uint256 amount1In0 = FullMath.mulDiv(amount1, priceX96, Q96);
            if (amount0 > amount1In0) {
                amount0 = amount1In0;
            }
            if (bestAmount < amount0) {
                bestAmount = amount0;
                bestPool = pool;
                priceX96OfBestPool = priceX96;
            }
        }

        if (bestPool == address(0)) revert("Pool not found");
    }

    function _prepare(
        address vault,
        address addressForApprove,
        address token,
        uint256 amount
    ) private returns (uint256[] memory tokenAmounts) {
        if (token == wrapperNativeToken && msg.value != 0) {
            amount = msg.value;
            IWrapperNativeToken(wrapperNativeToken).deposit{value: msg.value}();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        address[] memory tokens = IERC20RootVault(vault).vaultTokens();
        (, uint256[] memory tvl) = IERC20RootVault(vault).tvl();
        uint24[] memory fees_ = new uint24[](tokens.length);
        uint256 capital = 0;
        uint256[] memory tvlInToken = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 priceX96;
            address pool;
            if (tokens[i] == token) {
                priceX96 = Q96;
            } else {
                (pool, priceX96) = findBestPool(token, tokens[i]);
                if (IUniswapV3Pool(pool).token1() == token) {
                    priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
                }
                fees_[i] = IUniswapV3Pool(pool).fee();
                priceX96 = FullMath.mulDiv(priceX96, 1e6 - fees_[i], 1e6);
            }
            tvlInToken[i] = FullMath.mulDiv(tvl[i], Q96, priceX96);
            capital += tvlInToken[i];
        }

        uint256[] memory amountsForSwap = new uint256[](tokens.length);
        uint256 totalAmountForSwap = amount;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) continue;
            uint256 ratioX96 = FullMath.mulDiv(Q96, tvlInToken[i], capital);
            amountsForSwap[i] = FullMath.mulDiv(amount, ratioX96, Q96);
            if (totalAmountForSwap < amountsForSwap[i]) {
                amountsForSwap[i] = totalAmountForSwap;
                totalAmountForSwap = 0;
            } else {
                totalAmountForSwap -= amountsForSwap[i];
            }
        }

        if (IERC20(token).allowance(address(this), address(router)) == 0) {
            IERC20(token).safeApprove(address(router), type(uint256).max);
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) continue;
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: token,
                    tokenOut: tokens[i],
                    fee: fees_[i],
                    amountIn: amountsForSwap[i],
                    amountOutMinimum: 0,
                    deadline: type(uint256).max,
                    recipient: address(this),
                    sqrtPriceLimitX96: 0
                })
            );
        }

        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
            if (IERC20(tokens[i]).allowance(address(this), addressForApprove) == 0) {
                IERC20(tokens[i]).safeApprove(addressForApprove, type(uint256).max);
            }
        }
    }

    function _returnLeftovers(address vault, address token) private {
        address[] memory tokens = IERC20RootVault(vault).vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance != 0) {
                IERC20(tokens[i]).safeTransfer(msg.sender, balance);
            }
        }
        {
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance != 0) {
                IERC20(token).safeTransfer(msg.sender, balance);
            }
        }
    }

    function directDeposit(
        address vault,
        address token,
        uint256 amount,
        uint256 minLpAmount,
        bytes memory vaultOptions,
        bool needToReturnLeftovers
    ) external payable returns (uint256 lpAmount) {
        uint256[] memory tokenAmounts = _prepare(vault, vault, token, amount);
        IERC20RootVault(vault).deposit(tokenAmounts, minLpAmount, vaultOptions);
        lpAmount = IERC20(vault).balanceOf(address(this));
        IERC20(vault).safeTransfer(msg.sender, lpAmount);
        if (needToReturnLeftovers) {
            _returnLeftovers(vault, token);
        }
    }

    function wrappedDeposit(
        address wrapper,
        address vault,
        address token,
        uint256 amount,
        uint256 minLpAmount,
        bytes memory vaultOptions,
        bool needToReturnLeftovers
    ) external payable returns (uint256 lpAmount) {
        uint256[] memory tokenAmounts = _prepare(vault, wrapper, token, amount);
        DepositWrapper(wrapper).deposit(IERC20RootVault(vault), tokenAmounts, minLpAmount, vaultOptions);
        lpAmount = IERC20(vault).balanceOf(address(this));
        IERC20(vault).safeTransfer(msg.sender, lpAmount);
        if (needToReturnLeftovers) {
            _returnLeftovers(vault, token);
        }
    }
}
