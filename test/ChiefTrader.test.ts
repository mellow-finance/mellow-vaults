import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { randomAddress, withSigner } from "./library/Helpers";
import {
    ERC165_INTERFACE_ID,
    ERC165_INVALID_INTERFACE_ID,
    CHIEF_TRADER_INTERFACE_ID,
    TRADER_INTERFACE_ID,
} from "./library/constants";
import { ChiefTrader } from "./types/ChiefTrader";
import Exceptions from "./library/Exceptions";
import { setupDefaultContext, TestContext } from "./library/setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";

type CustomContext = {
    ownerSigner: SignerWithAddress;
};
type DeployOptions = {
    skipInit?: boolean;
};

// @ts-ignore
describe("ChiefTrader", function (this: TestContext<
    ChiefTrader,
    DeployOptions
> &
    CustomContext) {
    before(async () => {
        // @ts-ignore
        await setupDefaultContext.call(this);
        // @ts-ignore
        this.deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            this.subject = await ethers.getContractAt(
                "ChiefTrader",
                (
                    await deployments.get("ChiefTrader")
                ).address
            );
            this.uniV3Trader = await ethers.getContractAt(
                "UniV3Trader",
                (
                    await deployments.get("UniV3Trader")
                ).address
            );
            this.uniV2Trader = await ethers.getContractAt(
                "UniV2Trader",
                (
                    await deployments.get("UniV2Trader")
                ).address
            );
            this.protocolGovernance = await ethers.getContractAt(
                "ProtocolGovernance",
                (
                    await deployments.get("ProtocolGovernance")
                ).address
            );
        });
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#constructor", () => {
        it("deployes a new `ChiefTrader` contract", async () => {
            expect(ethers.constants.AddressZero).to.not.eq(
                this.subject.address
            );
        });

        it("initializes `ProtocolGovernance` address", async () => {
            expect(await this.subject.protocolGovernance()).to.eq(
                this.protocolGovernance.address
            );
        });

        describe("edge cases", () => {
            describe("when `protocolGovernance` argument is `0`", () => {
                it("reverts", async () => {
                    await expect(
                        deployments.deploy("ChiefTrader", {
                            from: this.deployer.address,
                            args: [ethers.constants.AddressZero],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO_EXCEPTION);
                });
            });
        });
    });

    describe("#tradersCount", () => {
        it("returns the number of traders", async () => {
            expect(await this.subject.tradersCount()).to.eq(2);
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).tradersCount()).to
                        .not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when a new trader is added", () => {
                it("`tradesCount` return value is increased by `1`", async () => {
                    const tradersCount = await this.subject.tradersCount();
                    const newTrader = await deployments.deploy("UniV3Trader", {
                        from: this.deployer.address,
                        args: [randomAddress()],
                        autoMine: true,
                    });
                    await this.subject
                        .connect(this.admin)
                        .addTrader(newTrader.address);
                    expect(await this.subject.tradersCount()).to.eq(
                        tradersCount.add(1)
                    );
                });
            });
        });
    });

    describe("#getTrader", () => {
        it("returns trader", async () => {
            expect(await this.subject.getTrader(1)).to.eq(
                this.uniV2Trader.address
            );
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).getTrader(1)).to
                        .not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when trader doesn't exist", () => {
                it("reverts", async () => {
                    await expect(this.subject.getTrader(1e5)).to.be.reverted;
                });
            });
        });
    });

    describe("#traders", () => {
        it("returns a list of registered trader addresses", async () => {
            expect(await this.subject.traders()).to.deep.eq([
                this.uniV3Trader.address,
                this.uniV2Trader.address,
            ]);
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(this.subject.connect(signer).traders()).to.not
                        .be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when a new trader is added", () => {
                it("new trader is included at the end of the list", async () => {
                    const newTrader = await deployments.deploy("UniV2Trader", {
                        from: this.deployer.address,
                        args: [randomAddress()],
                        autoMine: true,
                    });
                    await this.subject
                        .connect(this.admin)
                        .addTrader(newTrader.address);
                    expect(await this.subject.traders()).to.deep.eq([
                        this.uniV3Trader.address,
                        this.uniV2Trader.address,
                        newTrader.address,
                    ]);
                });
            });
        });
    });

    describe("#addTrader", () => {
        it("adds a new trader", async () => {
            const newTrader = await deployments.deploy("UniV2Trader", {
                from: this.deployer.address,
                args: [randomAddress()],
                autoMine: true,
            });
            await expect(
                this.subject.connect(this.admin).addTrader(newTrader.address)
            ).to.not.be.reverted;
        });

        it("emits `AddedTrader` event", async () => {
            const newTrader = await deployments.deploy("UniV2Trader", {
                from: this.deployer.address,
                args: [randomAddress()],
                autoMine: true,
            });
            expect(
                await this.subject
                    .connect(this.admin)
                    .addTrader(newTrader.address)
            ).to.emit(this.subject, "AddedTrader");
        });

        describe("access control", () => {
            it("denied: random address", async () => {
                withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .addTrader(this.uniV3Trader.address)
                    ).to.be.revertedWith(
                        Exceptions.PROTOCOL_ADMIN_REQUIRED_EXCEPTION
                    );
                });
            });
        });

        describe("edge cases", () => {
            xdescribe("when interfaces don't match", () => {
                it("reverts", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .addTrader(this.subject.address)
                    ).to.be.reverted;
                });
            });
        });
    });

    describe("#swapExactInput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {
                    const { weth, usdc } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactInput(
                            1e5,
                            ethers.constants.AddressZero,
                            weth,
                            usdc,
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });

            describe("when `token0` is not allowed", () => {
                it("reverts", async () => {
                    const { usdc } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactInput(
                            1,
                            this.uniV3Trader.address,
                            randomAddress(),
                            usdc,
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });

            describe("when `token1` is not allowed", () => {
                it("reverts", async () => {
                    const { weth } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactInput(
                            1,
                            this.uniV3Trader.address,
                            weth,
                            randomAddress(),
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });

            describe("when `token0 == token1`", () => {
                it("reverts", async () => {
                    const { weth } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactInput(
                            1,
                            this.uniV3Trader.address,
                            weth,
                            weth,
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });
        });
    });

    describe("#swapExactOutput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {
                    const { weth, usdc } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactOutput(
                            1e5,
                            ethers.constants.AddressZero,
                            weth,
                            usdc,
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });

            describe("when `token0` is not allowed", () => {
                it("reverts", async () => {
                    const { usdc } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactOutput(
                            1,
                            this.uniV3Trader.address,
                            randomAddress(),
                            usdc,
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });

            describe("when `token1` is not allowed", () => {
                it("reverts", async () => {
                    const { weth } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactOutput(
                            1,
                            this.uniV3Trader.address,
                            weth,
                            randomAddress(),
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });

            describe("when `token0 == token1`", () => {
                it("reverts", async () => {
                    const { weth } = await getNamedAccounts();
                    await expect(
                        this.subject.swapExactOutput(
                            1,
                            this.uniV3Trader.address,
                            weth,
                            weth,
                            1,
                            []
                        )
                    ).to.be.reverted;
                });
            });
        });
    });

    describe("#supportsInterface", () => {
        describe("returns `true` on IChiefTrader", async () => {
            it("returns `true`", async () => {
                expect(
                    await this.subject.supportsInterface(
                        CHIEF_TRADER_INTERFACE_ID
                    )
                ).to.be.true;
            });
        });

        it("returns `true` on ITrader", async () => {
            it("returns `true`", async () => {
                expect(
                    await this.subject.supportsInterface(TRADER_INTERFACE_ID)
                ).to.be.true;
            });
        });

        it("returns `true` on ERC165", async () => {
            it("returns `true`", async () => {
                expect(
                    await this.subject.supportsInterface(ERC165_INTERFACE_ID)
                ).to.be.true;
            });
        });

        it("returns `false` on `0xffffffff`", async () => {
            it("returns `false`", async () => {
                expect(
                    await this.subject.supportsInterface(
                        ERC165_INVALID_INTERFACE_ID
                    )
                ).to.be.false;
            });
        });
    });
});
