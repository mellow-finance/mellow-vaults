import { ethers, getNamedAccounts } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { mint } from "../library/Helpers";

async function mintUniV3Position_USDC_WETH(options: {
    tickLower: BigNumberish;
    tickUpper: BigNumberish;
    usdcAmount: BigNumberish;
    wethAmount: BigNumberish;
    fee: 3000 | 500;
}): Promise<any> {
    const { weth, usdc, deployer, uniswapV3PositionManager } =
        await getNamedAccounts();

    const wethContract = await ethers.getContractAt("WETH", weth);
    const usdcContract = await ethers.getContractAt("ERC20Token", usdc);

    const positionManagerContract = await ethers.getContractAt(
        INonfungiblePositionManager,
        uniswapV3PositionManager
    );

    await mint("WETH", deployer, options.wethAmount);
    await mint("USDC", deployer, options.usdcAmount);

    console.log(
        "weth balance",
        (await wethContract.balanceOf(deployer)).toString()
    );
    console.log(
        "usdc balance",
        (await usdcContract.balanceOf(deployer)).toString()
    );

    if (
        (await wethContract.allowance(deployer, uniswapV3PositionManager)).eq(
            BigNumber.from(0)
        )
    ) {
        await wethContract.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
        console.log(
            `approved weth at ${weth} to uniswapV3PositionManager at ${uniswapV3PositionManager}`
        );
    }
    if (
        (await usdcContract.allowance(deployer, uniswapV3PositionManager)).eq(
            BigNumber.from(0)
        )
    ) {
        await usdcContract.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
        console.log(
            `approved usdc at ${usdc} to uniswapV3PositionManager at ${uniswapV3PositionManager}`
        );
    }

    const mintParams = {
        token0: usdc,
        token1: weth,
        fee: options.fee,
        tickLower: -60,
        tickUpper: 60,
        amount0Desired: options.usdcAmount,
        amount1Desired: options.wethAmount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: deployer,
        deadline: ethers.constants.MaxUint256,
    };

    console.log(`minting new uni v3 position for deployer at ${deployer} 
    \n with params ${JSON.stringify(mintParams)}`);

    const result = await positionManagerContract.callStatic.mint(mintParams);
    await positionManagerContract.mint(mintParams);
    return result;
}

describe("rebalance", () => {
    it("mints univ3 position", async () => {
        const result = await mintUniV3Position_USDC_WETH({
            fee: 3000,
            tickLower: -60,
            tickUpper: 60,
            usdcAmount: 300000000,
            wethAmount: 100000000,
        });
        console.log(result);
    });
});
