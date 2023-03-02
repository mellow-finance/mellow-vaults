// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/univ2/periphery/IWETH.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/curve/I3Pool.sol";
import "../interfaces/external/lido/IWSTETH.sol";
import "../interfaces/external/lido/ISTETH.sol";
import "../libraries/external/FullMath.sol";
import "./FarmWrapper.sol";

contract LidoDepositWrapper {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    uint256 public constant ETH_OPTION = 0;
    uint256 public constant WETH_OPTION = 1;
    uint256 public constant STETH_OPTION = 2;
    uint256 public constant WSTETH_OPTION = 3;

    uint256 public constant SWAP_OPTION = 0;
    uint256 public constant STAKE_OPTION = 0;

    uint256 public constant D18 = 10**18;
    uint256 public constant Q96 = 2**96;

    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public constant curvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant uniswapPool = 0xD340B57AAcDD10F96FC1CF10e15921936F41E29c;

    using SafeERC20 for IERC20;

    receive() external payable {}

    function deposit(
        IERC20RootVault rootVault,
        uint256 option,
        uint256 stakeOption,
        uint256 amount,
        uint256 minLpTokens,
        bytes calldata vaultOptions
    ) external payable {
        require(option <= 3, ExceptionsLibrary.INVARIANT);

        (uint256[] memory minTvl, ) = rootVault.tvl();
        uint256 wethShareD18;
        uint256 wethTvl;

        {
            (uint256 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
            uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
            wethTvl = minTvl[1] + FullMath.mulDiv(minTvl[0], priceX96, Q96);
        }

        wethShareD18 = FullMath.mulDiv(minTvl[1], D18, wethTvl);

        if (option == ETH_OPTION) {
            uint256 ethAmount = msg.value;
            _ethToWeth(FullMath.mulDiv(ethAmount, wethShareD18, D18));
            _ethToWsteth(FullMath.mulDiv(ethAmount, D18 - wethShareD18, D18), stakeOption);
        } else if (option == WETH_OPTION) {
            IERC20(weth).safeTransferFrom(msg.sender, address(this), amount);
            _wethToWsteth(FullMath.mulDiv(amount, D18 - wethShareD18, D18), stakeOption);
        } else if (option == STETH_OPTION) {
            IERC20(steth).safeTransferFrom(msg.sender, address(this), amount);
            _stethToWeth(FullMath.mulDiv(amount, wethShareD18, D18));
            _stethToWsteth(FullMath.mulDiv(amount, D18 - wethShareD18, D18));
        } else {
            IERC20(wsteth).safeTransferFrom(msg.sender, address(this), amount);
            _wstethToWeth(FullMath.mulDiv(amount, wethShareD18, D18));
        }

        uint256 token0Balance = IERC20(wsteth).balanceOf(address(this));
        uint256 token1Balance = IERC20(weth).balanceOf(address(this));

        uint256[] memory balances = new uint256[](2);
        balances[0] = token0Balance;
        balances[1] = token1Balance;

        IERC20(weth).safeIncreaseAllowance(address(rootVault), token1Balance);
        IERC20(wsteth).safeIncreaseAllowance(address(rootVault), token0Balance);

        rootVault.deposit(balances, minLpTokens, vaultOptions);

        IERC20(weth).safeApprove(address(rootVault), 0);
        IERC20(wsteth).safeApprove(address(rootVault), 0);

        rootVault.safeTransfer(msg.sender, rootVault.balanceOf(address(this)));
        IERC20(weth).safeTransfer(msg.sender, IERC20(weth).balanceOf(address(this)));
        IERC20(wsteth).safeTransfer(msg.sender, IERC20(wsteth).balanceOf(address(this)));
    }

    function _ethToWeth(uint256 amount) internal {
        IWETH(weth).deposit{value: amount}();
    }

    function _ethToWsteth(uint256 amount, uint256 stakeOption) internal {
        if (stakeOption == SWAP_OPTION) {
            I3Pool(curvePool).exchange{value: amount}(0, 1, amount, 0);
        } else {
            ISTETH(steth).submit{value: amount}(address(this));
        }

        uint256 stethAmount = IERC20(steth).balanceOf(address(this));
        IERC20(steth).safeIncreaseAllowance(address(wsteth), stethAmount);
        IwstETH(wsteth).wrap(stethAmount);
    }

    function _wethToWsteth(uint256 amount, uint256 stakeOption) internal {
        IWETH(weth).withdraw(amount);
        _ethToWsteth(amount, stakeOption);
    }

    function _stethToWsteth(uint256 amount) internal {
        IERC20(steth).safeIncreaseAllowance(address(wsteth), amount);
        IwstETH(wsteth).wrap(amount);
    }

    function _stethToWeth(uint256 amount) internal {
        IERC20(steth).safeIncreaseAllowance(address(curvePool), amount);
        I3Pool(curvePool).exchange(1, 0, amount, 0);
        uint256 balance = address(this).balance;
        IWETH(weth).deposit{value: balance}();
    }

    function _wstethToWeth(uint256 amount) internal {
        IwstETH(wsteth).unwrap(amount);
        uint256 stethAmount = IERC20(steth).balanceOf(address(this));
        _stethToWeth(stethAmount);
    }
}
