import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "ethers";
import { Contract } from "@ethersproject/contracts";
import { UniV2Trader } from "./types/UniV2Trader";
import { PathItemStruct } from "./types/IUniV2Trader";
import {
    ERC165_INTERFACE_ID,
    TRADER_INTERFACE_ID,
    ZERO_INTERFACE_ID,
} from "./library/Constants";
import {
    depositW9,
    depositWBTC,
    approveERC20,
    randomAddress,
    encodeToBytes,
    now,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";

xdescribe("UniV2Trader", () => {
    let deploymentFixture: Function;
    let uniV2Trader: UniV2Trader;
    let deployer: string;
    let weth: string;
    let wbtc: string;
    let wbtcContract: Contract;
    let wethContract: Contract;

    before(async () => {
        const { get } = deployments;
        ({ deployer, weth, wbtc } = await getNamedAccounts());
        wbtcContract = await ethers.getContractAt("IERC20", wbtc);
        wethContract = await ethers.getContractAt("IERC20", weth);

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            uniV2Trader = await ethers.getContractAt(
                "UniV2Trader",
                (
                    await get("UniV2Trader")
                ).address
            );
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
    });

    describe("#constructor", () => {
        describe("when passed zero address", () => {
            it("reverts with `ZERO_ADDRESS_EXCEPTION`", async () => {
                await expect(
                    (
                        await ethers.getContractFactory("UniV2Trader")
                    ).deploy(ethers.constants.AddressZero)
                ).to.be.revertedWith("AZ");
            });
        });

        describe("happy case", () => {
            it("has correct router address", async () => {
                const { uniswapV2Router02 } = await getNamedAccounts();
                const trader = await (
                    await ethers.getContractFactory("UniV2Trader")
                ).deploy(uniswapV2Router02);
                expect(await trader.router()).to.eql(uniswapV2Router02);
            });
        });
    });

    describe("swaps:", () => {
        let swapsDeploymentFixture: Function;

        before(async () => {
            swapsDeploymentFixture = deployments.createFixture(async () => {
                await deployments.fixture();
                await depositW9(deployer, ethers.utils.parseEther("1")); // 1 WETH
                await depositWBTC(deployer, BigNumber.from(10).pow(8)); // 1 WBTC
                await approveERC20(weth, uniV2Trader.address);
                await approveERC20(wbtc, uniV2Trader.address);
            });
        });

        beforeEach(async () => {
            await swapsDeploymentFixture();
        });

        describe("#swapExactInput", () => {
            describe("when passed empty path", () => {
                it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                    await expect(
                        uniV2Trader.swapExactInput(
                            0,
                            BigNumber.from(10).pow(3),
                            deployer,
                            [],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                });
            });

            describe("when passed not linked path", () => {
                it("reverts with `INVALID_VALUE`", async () => {
                    await expect(
                        uniV2Trader.swapExactInput(
                            0,
                            BigNumber.from(10).pow(3),
                            deployer,
                            [
                                {
                                    token0: weth,
                                    token1: wbtc,
                                    options: [],
                                },
                                {
                                    token0: randomAddress(),
                                    token1: randomAddress(),
                                    options: [],
                                },
                            ],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                });
            });

            describe("when passed a path that contains zero address", () => {
                it("reverts with `INVALID_VALUE`", async () => {
                    await expect(
                        uniV2Trader.swapExactInput(
                            0,
                            BigNumber.from(10).pow(3),
                            deployer,
                            [
                                {
                                    token0: ethers.constants.AddressZero,
                                    token1: wbtc,
                                    options: [],
                                },
                                {
                                    token0: wbtc,
                                    token1: weth,
                                    options: [],
                                },
                            ],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                });
            });

            describe("happy case", () => {
                it("swaps exact input tokens for output", async () => {
                    const amount = BigNumber.from(10).pow(3);
                    const options = encodeToBytes(
                        ["tuple(uint256 deadline, uint256 limitAmount)"],
                        [
                            {
                                deadline: now(),
                                limitAmount: amount.mul(5),
                            },
                        ]
                    );
                    const initialAmountIn = await wbtcContract.balanceOf(
                        deployer
                    );
                    const initialAmountOut = await wethContract.balanceOf(
                        deployer
                    );
                    const amountOut =
                        await uniV2Trader.callStatic.swapExactInput(
                            0,
                            amount,
                            deployer,
                            [
                                {
                                    token0: wbtc,
                                    token1: weth,
                                    options: [],
                                },
                            ] as PathItemStruct[],
                            options
                        );
                    await expect(
                        uniV2Trader.swapExactInput(
                            0,
                            amount,
                            deployer,
                            [
                                {
                                    token0: wbtc,
                                    token1: weth,
                                    options: [],
                                },
                            ] as PathItemStruct[],
                            options
                        )
                    ).to.not.be.reverted;
                    expect(await wbtcContract.balanceOf(deployer)).to.eql(
                        initialAmountIn.sub(amount)
                    );
                    expect(await wethContract.balanceOf(deployer)).to.eql(
                        initialAmountOut.add(amountOut)
                    );
                });
            });
        });

        xdescribe("#swapExactOutput", () => {
            describe("happy case", () => {
                it("swaps input tokens for exact output tokens", async () => {
                    const amount = BigNumber.from(1);
                    const options = encodeToBytes(
                        ["tuple(uint256 deadline, uint256 limitAmount)"],
                        [
                            {
                                deadline: now(),
                                limitAmount: BigNumber.from(10).pow(18),
                            },
                        ]
                    );
                    const amountIn =
                        await uniV2Trader.callStatic.swapExactOutput(
                            0,
                            amount,
                            deployer,
                            [
                                {
                                    token0: weth,
                                    token1: wbtc,
                                    options: [],
                                },
                            ],
                            options
                        );
                    console.log("amountIn", amountIn);
                });
            });
        });
    });

    describe("#supportsInterface", () => {
        describe("when passed ERC165 interface", () => {
            it("returns `true`", async () => {
                expect(await uniV2Trader.supportsInterface(ERC165_INTERFACE_ID))
                    .to.be.true;
            });
        });

        describe("when passed ITrader interface", () => {
            it("returns `true`", async () => {
                expect(await uniV2Trader.supportsInterface(TRADER_INTERFACE_ID))
                    .to.be.true;
            });
        });

        describe("when passed zero", () => {
            it("returns `false`", async () => {
                expect(await uniV2Trader.supportsInterface(ZERO_INTERFACE_ID))
                    .to.be.false;
            });
        });
    });
});
