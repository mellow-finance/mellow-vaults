// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/oracles/IOracle.sol";
import "../interfaces/vaults/ISqueethVaultGovernance.sol";
import "../interfaces/external/squeeth/IController.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/CommonLibrary.sol";
import "hardhat/console.sol";

contract SqueethHelper {
    uint256 public immutable D18 = 10**18;
    uint256 public immutable D9 = 10**9;
    uint256 public immutable D6 = 10**6;
    uint256 public immutable D4 = 10**4;

    IController private controller;
    address private wPowerPerp;
    address private weth;
    address private wPowerPerpPool;
    uint32 public immutable TWAP_PERIOD;

    constructor(IController controller_) {
        controller = controller_;
        weth = controller_.weth();
        wPowerPerp = controller_.wPowerPerp();
        TWAP_PERIOD = controller_.TWAP_PERIOD();
        wPowerPerpPool = controller_.wPowerPerpPool();
    }

    function spotPrice(address tokenIn, address pool) public view returns (uint256 priceD18) {
        (uint160 poolSqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        uint256 priceX96 = FullMath.mulDiv(poolSqrtPriceX96, poolSqrtPriceX96, CommonLibrary.Q96); //TODO: check type convertion
        priceX96 = FullMath.mulDiv(
            priceX96,
            10**ERC20(IUniswapV3Pool(pool).token0()).decimals(),
            10**ERC20(IUniswapV3Pool(pool).token1()).decimals()
        );
        if (tokenIn == IUniswapV3Pool(pool).token1()) {
            priceX96 = FullMath.mulDiv(CommonLibrary.Q96, CommonLibrary.Q96, priceX96);
        }
        priceD18 = FullMath.mulDiv(priceX96, D18, CommonLibrary.Q96);
    }

    function getMinMaxPrice(
        IOracle oracle,
        address token0,
        address token1
    ) public view returns (uint256 minPriceX96, uint256 maxPriceX96) {
        (uint256[] memory prices, ) = oracle.priceX96(token0, token1, 0x2A);
        require(prices.length > 1, ExceptionsLibrary.INVARIANT);
        minPriceX96 = prices[0];
        maxPriceX96 = prices[0];
        for (uint32 i = 1; i < prices.length; ++i) {
            if (prices[i] < minPriceX96) {
                minPriceX96 = prices[i];
            } else if (prices[i] > maxPriceX96) {
                maxPriceX96 = prices[i];
            }
        }
    }

    function twapIndexPrice() public view returns (uint256 indexPrice) {
        indexPrice = CommonLibrary.sqrt(controller.getUnscaledIndex(TWAP_PERIOD)) * D9;
    }

    function openRecollateraizedAmounts(
        uint256 wethAmount,
        uint256 collateralFactorD9,
        address vaultGovernance
    )
        external
        view
        returns (
            uint256 wethToBorrow,
            uint256 newWethAmount,
            uint256 wPowerPerpAmountExpected
        )
    {
        uint256 spotPriceD18 = spotPrice(wPowerPerp, wPowerPerpPool);
        uint256 indexPriceNormalized = FullMath.mulDiv(
            twapIndexPrice(),
            controller.getExpectedNormalizationFactor(),
            D18
        );
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(vaultGovernance)
            .delayedProtocolParams();
        uint256 wethFromCollateralWeiD9 = FullMath.mulDiv(spotPriceD18, D4 * D9, indexPriceNormalized);
        console.log("depeg");
        console.log(wethFromCollateralWeiD9);
        console.log(protocolParams.maxDepegD9);
        if (wethFromCollateralWeiD9 <= protocolParams.maxDepegD9 + D9) {
            wethFromCollateralWeiD9 = FullMath.mulDiv(
                wethFromCollateralWeiD9,
                D9 - protocolParams.slippageD9,
                collateralFactorD9
            );
            wethToBorrow = FullMath.mulDiv(
                wethAmount,
                wethFromCollateralWeiD9,
                D9 +
                    FullMath.mulDiv(IUniswapV3Pool(protocolParams.wethBorrowPool).fee(), D9, D6) -
                    wethFromCollateralWeiD9
            );
            newWethAmount = wethAmount + wethToBorrow;
            uint256 mintedETHAmount = FullMath.mulDiv(newWethAmount, D9, collateralFactorD9);
            wPowerPerpAmountExpected = FullMath.mulDiv(mintedETHAmount, D4 * D18, indexPriceNormalized);
        }
    }

    function openAmounts(uint256 wethAmount, uint256 collateralFactorD9)
        external
        view
        returns (uint256 wPowerPerpAmountExpected)
    {
        uint256 ethPriceNormalized = FullMath.mulDiv(
            twapIndexPrice(),
            controller.getExpectedNormalizationFactor(),
            D18
        );
        uint256 mintedETHAmount = FullMath.mulDiv(wethAmount, D9, collateralFactorD9);
        wPowerPerpAmountExpected = FullMath.mulDiv(mintedETHAmount, D18 * D4, ethPriceNormalized);
    }

    function closeAmounts(uint256 wPowerPerpRemaining, address vaultGovernance)
        external
        view
        returns (uint256 wethToBorrow, uint256 wethAmountMax)
    {
        uint256 wethNeeded = FullMath.mulDiv(wPowerPerpRemaining, spotPrice(wPowerPerp, wPowerPerpPool), D18);
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(vaultGovernance)
            .delayedProtocolParams();
        wethAmountMax = FullMath.mulDiv(wethNeeded, D9, D9 - protocolParams.slippageD9); //TODO: add fees
        uint256 wethBalance = IERC20(weth).balanceOf(address(msg.sender));
        wethToBorrow = wethAmountMax > wethBalance ? wethAmountMax - wethBalance : 0;
    }

    function minMaxAmounts(
        uint256 wethAmount,
        uint256 wPowerPerpDebt,
        address vaultGovernance
    ) external view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);
        minTokenAmounts[0] = wethAmount;
        maxTokenAmounts = minTokenAmounts;
        uint256 wPowerPerpBalance = IERC20(wPowerPerp).balanceOf(address(msg.sender));
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(vaultGovernance)
            .delayedProtocolParams();
        (uint256 minPriceX96, uint256 maxPriceX96) = getMinMaxPrice(protocolParams.oracle, wPowerPerp, weth);
        if (wPowerPerpDebt > wPowerPerpBalance) {
            minTokenAmounts[0] -= FullMath.mulDiv(wPowerPerpDebt - wPowerPerpBalance, maxPriceX96, CommonLibrary.Q96);
            maxTokenAmounts[0] -= FullMath.mulDiv(wPowerPerpDebt - wPowerPerpBalance, minPriceX96, CommonLibrary.Q96);
        } else {
            minTokenAmounts[0] += FullMath.mulDiv(wPowerPerpBalance - wPowerPerpDebt, minPriceX96, CommonLibrary.Q96);
            maxTokenAmounts[0] += FullMath.mulDiv(wPowerPerpBalance - wPowerPerpDebt, maxPriceX96, CommonLibrary.Q96);
        }
    }
}
