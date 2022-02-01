import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    sleep,
    mintUniV3Position_USDC_WETH,
    encodeToBytes,
    decodeFromBytes, withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { ISwapRouter } from "../types";
import { ExactInputSingleParamsStruct } from "../types/ISwapRouter";

type CustomContext = {
    uniV3Router: string;
    uniswapV2Router02: string;
    curveRouter: string;
};

type DeployOptions = {};

contract<ERC20Vault, DeployOptions, CustomContext>(
    "externalCallTest",
    function () {
        const poolFee = 3000;
        const APPROVE_SELECTOR = "0x095ea7b3";
        const EXACT_INPUT_SINGLE_SELECTOR = "0x414bf389";
        const SWAP_TOKENS_FOR_TOKENS_SELECTOR = "0x5c11d795";
        const CURVE_EXCHANGE_SELECTOR = "0x3df02124";

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    const { uniswapV3Router, uniswapV2Router02, test } =
                        await getNamedAccounts();

                    this.uniV3Router = uniswapV3Router;
                    this.uniswapV2Router02 = uniswapV2Router02;
                    this.curveRouter = "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7";

                    await this.protocolGovernance.validators(this.curveRouter);

                    const tokens = [this.weth.address, this.usdc.address, this.dai.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    let erc20VaultNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );
                    this.subject = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );

                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
                    await mint(
                        "WETH",
                        this.subject.address,
                        BigNumber.from(10).pow(18).mul(300)
                    );

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    for (var routerAddress of [this.uniV3Router, this.uniswapV2Router02, this.curveRouter]) {
                        await this.subject.externalCall(
                            this.weth.address,
                            APPROVE_SELECTOR,
                            encodeToBytes(
                                ["address", "uint256"],
                                [routerAddress, ethers.constants.MaxUint256]
                            )
                        );
                        const tx = await this.subject.populateTransaction.externalCall(
                            this.usdc.address,
                            APPROVE_SELECTOR,
                            encodeToBytes(
                                ["address", "uint256"],
                                [routerAddress, ethers.constants.MaxUint256]
                            )
                        );
                        const r = await this.deployer.sendTransaction(tx);
                        const z = await r.wait();
                        // console.log("%s %s", r, z);
                        // console.log(z.logs);
                    }
                    console.log("check");
                    console.log(await this.weth.allowance(this.subject.address, this.uniV3Router));
                    console.log(await this.usdc.allowance(this.subject.address, this.uniV3Router));
                    console.log(await this.weth.allowance(this.subject.address, this.uniswapV2Router02));
                    console.log(await this.usdc.allowance(this.subject.address, this.uniswapV2Router02));
                    console.log(this.subject.address);
                    console.log("%s %s", this.usdc.address, this.curveRouter);
                    let x = encodeToBytes(
                                ["address", "uint256"],
                                [this.curveRouter, ethers.constants.MaxUint256]
                    );
                    console.log(x);
                    console.log(await this.usdc.allowance(this.subject.address, this.curveRouter));
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe.only("singleSwap", () => {
            it("uniswapV3", async () => {
                let swapParams = {
                    tokenIn: this.weth.address,
                    tokenOut: this.usdc.address,
                    fee: poolFee,
                    recipient: this.subject.address,
                    deadline: ethers.constants.MaxUint256,
                    amountIn: BigNumber.from(10).pow(18).mul(1),
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0,
                };

                await this.subject.externalCall(
                    this.uniV3Router,
                    EXACT_INPUT_SINGLE_SELECTOR,
                    encodeToBytes(
                        [
                            "tuple(" +
                                "address tokenIn, " +
                                "address tokenOut, " +
                                "uint24 fee, " +
                                "address recipient, " +
                                "uint256 deadline, " +
                                "uint256 amountIn, " +
                                "uint256 amountOutMinimum, " +
                                "uint160 sqrtPriceLimitX96)",
                        ],
                        [swapParams]
                    )
                );
            });

            it("uniswapV2", async () => {
                await this.subject.externalCall(
                    this.uniswapV2Router02,
                    SWAP_TOKENS_FOR_TOKENS_SELECTOR,
                    encodeToBytes(
                        ["uint", "uint", "address[]", "address", "uint"],
                        [
                            BigNumber.from(10).pow(18).mul(1),
                            0,
                            [this.weth.address, this.usdc.address],
                            this.subject.address,
                            ethers.constants.MaxUint256,
                        ]
                    )
                );
            });

            it("curve", async () => {
                console.log(await this.usdc.allowance(this.subject.address, this.curveRouter));
                console.log(await this.usdc.balanceOf(this.subject.address));
                await this.subject.externalCall(
                    this.curveRouter,
                    CURVE_EXCHANGE_SELECTOR,
                    encodeToBytes(
                        ["int128", "int128", "uint256", "uint256"],
                        [1, 0, BigNumber.from(10).pow(6).mul(1), 0]
                    )
                );
            })
        });
    }
);
