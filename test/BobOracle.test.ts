import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint } from "./library/Helpers";
import { contract } from "./library/setup";
import {
    BobOracle,
    IUniswapV3Pool,
    ISwapRouter as SwapRouterInterface,
    ERC20Token,
} from "./types";
import { TRANSACTION_GAS_LIMITS } from "../deploy/0000_utils";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { expect } from "chai";

type CustomContext = {
    pool: IUniswapV3Pool;
    swapRouter: SwapRouterInterface;
    bob: ERC20Token;
};

type DeployOptions = {};

contract<BobOracle, DeployOptions, CustomContext>("BobOracle", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { deploy } = deployments;
                const { deployer, usdc, bob, uniswapV3Router } =
                    await getNamedAccounts();
                const factory = await ethers.getContractAt(
                    "IUniswapV3Factory",
                    "0x1F98431c8aD98523631AE4a59f267346ea31F984"
                );

                const poolAddress = await factory.getPool(usdc, bob, 100);

                this.pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    poolAddress
                );

                await deploy("BobOracle", {
                    from: deployer,
                    args: [
                        usdc,
                        bob,
                        this.pool.address,
                        "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
                    ],
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS,
                });

                this.bob = await ethers.getContractAt("ERC20Token", bob);
                this.subject = await ethers.getContract("BobOracle");

                this.swapRouter = await ethers.getContractAt(
                    ISwapRouter,
                    uniswapV3Router
                );
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#latestRoundData", () => {
        it("#check correctness", async () => {
            const initialPrice = (
                await this.subject.latestRoundData()
            ).answer.toNumber();

            await mint(
                "USDC",
                this.deployer.address,
                BigNumber.from(10).pow(15)
            );
            await this.usdc.approve(
                this.swapRouter.address,
                ethers.constants.MaxUint256
            );

            // increase bob token price
            await this.swapRouter.exactInputSingle({
                tokenIn: this.usdc.address,
                tokenOut: this.bob.address,
                fee: 100,
                recipient: this.deployer.address,
                deadline: ethers.constants.MaxUint256,
                amountIn: BigNumber.from(10).pow(6).mul(100000),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            });
            const bobPricePlus = (
                await this.subject.latestRoundData()
            ).answer.toNumber();

            await this.bob.approve(
                this.swapRouter.address,
                ethers.constants.MaxUint256
            );
            // decrease bob token price
            await this.swapRouter.exactInputSingle({
                tokenIn: this.bob.address,
                tokenOut: this.usdc.address,
                fee: 100,
                recipient: this.deployer.address,
                deadline: ethers.constants.MaxUint256,
                amountIn: BigNumber.from(10).pow(18).mul(95000),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            });
            const bobPriceMinus = (
                await this.subject.latestRoundData()
            ).answer.toNumber();

            expect(initialPrice).to.be.closeTo(10 ** 8, 10 ** 5);
            expect(initialPrice).to.be.lt(bobPricePlus);
            expect(bobPricePlus).to.be.gt(bobPriceMinus);
        });
    });
});
