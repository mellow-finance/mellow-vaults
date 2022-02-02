import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    encodeToBytes,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20Vault } from "../types";
import { setupVault } from "../../deploy/0000_utils";
import { expect } from "chai";
import Exceptions from "../library/Exceptions";

type CustomContext = {
    uniswapV3Router: string;
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
        const SWAP_EXACT_TOKENS_FOR_TOKENS_SELECTOR = "0x38ed1739";
        const CURVE_EXCHANGE_SELECTOR = "0x3df02124";

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    const { uniswapV3Router, uniswapV2Router02 } =
                        await getNamedAccounts();

                    this.uniswapV3Router = uniswapV3Router;
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

                    for (let token of [this.usdc, this.weth]) {
                        await token.approve(
                            this.subject.address,
                            ethers.constants.MaxUint256
                        );
                    }

                    for (let routerAddress of [this.uniswapV3Router, this.uniswapV2Router02, this.curveRouter]) {
                        await this.subject.externalCall(
                            this.weth.address,
                            APPROVE_SELECTOR,
                            encodeToBytes(
                                ["address", "uint256"],
                                [routerAddress, ethers.constants.MaxUint256]
                            )
                        );
                        await this.subject.externalCall(
                            this.usdc.address,
                            APPROVE_SELECTOR,
                            encodeToBytes(
                                ["address", "uint256"],
                                [routerAddress, ethers.constants.MaxUint256]
                            )
                        );
                    }
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe.only("correct swap", () => {
            it("uniswapV3", async () => {
                let startBalanceUSDC = await this.usdc.balanceOf(this.subject.address);
                let startBalanceWETH = await this.weth.balanceOf(this.subject.address);

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
                    this.uniswapV3Router,
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

                let currentBalanceUSDC = await this.usdc.balanceOf(this.subject.address);
                let currentBalanceWETH = await this.weth.balanceOf(this.subject.address);
                expect(currentBalanceUSDC > startBalanceUSDC);
                expect(currentBalanceWETH < startBalanceWETH);
            });

            it("uniswapV2", async () => {
                let startBalanceUSDC = await this.usdc.balanceOf(this.subject.address);
                let startBalanceWETH = await this.weth.balanceOf(this.subject.address);

                await this.subject.externalCall(
                    this.uniswapV2Router02,
                    SWAP_EXACT_TOKENS_FOR_TOKENS_SELECTOR,
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

                let currentBalanceUSDC = await this.usdc.balanceOf(this.subject.address);
                let currentBalanceWETH = await this.weth.balanceOf(this.subject.address);
                expect(currentBalanceUSDC > startBalanceUSDC);
                expect(currentBalanceWETH < startBalanceWETH);
            });

            it("curve", async () => {
                let startBalanceUSDC = await this.usdc.balanceOf(this.subject.address);
                let startBalanceDAI = await this.dai.balanceOf(this.subject.address);

                await this.subject.externalCall(
                    this.curveRouter,
                    CURVE_EXCHANGE_SELECTOR,
                    encodeToBytes(
                        ["int128", "int128", "uint256", "uint256"],
                        [1, 0, BigNumber.from(10).pow(6).mul(1), 0]
                    )
                );

                let currentBalanceUSDC = await this.usdc.balanceOf(this.subject.address);
                let currentBalanceDAI = await this.dai.balanceOf(this.subject.address);
                expect(currentBalanceUSDC < startBalanceUSDC);
                expect(currentBalanceDAI > startBalanceDAI);
            })
        });

        describe.only("reverted swap", () => {
            describe("huge amountOutMinimum", () => {
                it("uniswapV3", async () => {
                    let swapParams = {
                        tokenIn: this.weth.address,
                        tokenOut: this.usdc.address,
                        fee: poolFee,
                        recipient: this.subject.address,
                        deadline: ethers.constants.MaxUint256,
                        amountIn: BigNumber.from(10).pow(18).mul(1),
                        amountOutMinimum: ethers.constants.MaxUint256,
                        sqrtPriceLimitX96: 0,
                    };

                    await expect(this.subject.externalCall(
                        this.uniswapV3Router,
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
                    )).to.be.revertedWith("Too little received");
                });

                it("uniswapV2", async () => {
                    await expect(this.subject.externalCall(
                        this.uniswapV2Router02,
                        SWAP_EXACT_TOKENS_FOR_TOKENS_SELECTOR,
                        encodeToBytes(
                            ["uint", "uint", "address[]", "address", "uint"],
                            [
                                BigNumber.from(10).pow(18).mul(1),
                                ethers.constants.MaxUint256,
                                [this.weth.address, this.usdc.address],
                                this.subject.address,
                                ethers.constants.MaxUint256,
                            ]
                        )
                    )).to.be.revertedWith("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
                });

                it("curve", async () => {
                    await expect(this.subject.externalCall(
                        this.curveRouter,
                        CURVE_EXCHANGE_SELECTOR,
                        encodeToBytes(
                            ["int128", "int128", "uint256", "uint256"],
                            [1, 0, BigNumber.from(10).pow(6).mul(1), ethers.constants.MaxUint256]
                        )
                    )).to.be.revertedWith("Exchange resulted in fewer coins than expected");
                })
            });

            describe("early deadline", () => {
                it("uniswapV3", async () => {
                    let swapParams = {
                        tokenIn: this.weth.address,
                        tokenOut: this.usdc.address,
                        fee: poolFee,
                        recipient: this.subject.address,
                        deadline: 0,
                        amountIn: BigNumber.from(10).pow(18).mul(1),
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0,
                    };

                    await expect(this.subject.externalCall(
                        this.uniswapV3Router,
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
                    )).to.be.revertedWith("Transaction too old");
                });

                it("uniswapV2", async () => {
                    await expect(this.subject.externalCall(
                        this.uniswapV2Router02,
                        SWAP_EXACT_TOKENS_FOR_TOKENS_SELECTOR,
                        encodeToBytes(
                            ["uint", "uint", "address[]", "address", "uint"],
                            [
                                BigNumber.from(10).pow(18).mul(1),
                                0,
                                [this.weth.address, this.usdc.address],
                                this.subject.address,
                                0,
                            ]
                        )
                    )).to.be.revertedWith("UniswapV2Router: EXPIRED");
                });
            });

            describe("insufficient amount of token", () => {
                it("uniswapV3", async () => {
                    let swapParams = {
                        tokenIn: this.weth.address,
                        tokenOut: this.usdc.address,
                        fee: poolFee,
                        recipient: this.subject.address,
                        deadline: ethers.constants.MaxUint256,
                        amountIn: BigNumber.from(10).pow(18).mul(10000),
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0,
                    };

                    await expect(this.subject.externalCall(
                        this.uniswapV3Router,
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
                    )).to.be.revertedWith(Exceptions.SAFE_TRANSFER_FROM_FAILED);
                });

                it("uniswapV2", async () => {
                    await expect(this.subject.externalCall(
                        this.uniswapV2Router02,
                        SWAP_EXACT_TOKENS_FOR_TOKENS_SELECTOR,
                        encodeToBytes(
                            ["uint", "uint", "address[]", "address", "uint"],
                            [
                                BigNumber.from(10).pow(18).mul(10000),
                                0,
                                [this.weth.address, this.usdc.address],
                                this.subject.address,
                                ethers.constants.MaxUint256,
                            ]
                        )
                    )).to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED");
                });

                it("curve", async () => {
                    await expect(this.subject.externalCall(
                        this.curveRouter,
                        CURVE_EXCHANGE_SELECTOR,
                        encodeToBytes(
                            ["int128", "int128", "uint256", "uint256"],
                            [1, 0, BigNumber.from(10).pow(18).mul(1), 0]
                        )
                    )).to.be.reverted;
                })
            });
        });

    }
);
