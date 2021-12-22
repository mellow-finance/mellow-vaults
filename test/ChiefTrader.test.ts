import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
} from "./library/Helpers";
import { ChiefTrader } from "./types/ChiefTrader";
import Exceptions from "./library/Exceptions";
import { setupDefaultContext, TestContext } from "./library/setup";
import { address, pit } from "./library/property";
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
                it("`tradesCount` return value is increased by `1`", async () => {});
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
                xit("returns zero address", async () => {
                    expect(await this.subject.getTrader(1e5)).to.eq(
                        ethers.constants.AddressZero
                    ).to.be.reverted;
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
                it("new trader is included at the end of the list", async () => {});
            });
        });
    });

    describe("#addTrader", () => {
        it("adds a new trader", async () => {});

        it("emits `AddedTrader` event", async () => {});

        describe("access control", () => {
            describe("denied: random address", () => {});
        });

        describe("edge cases", () => {
            describe("when interfaces don't match", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#swapExactInput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {});
            });

            describe("when a path contains not allowed token", () => {});
        });
    });

    describe("#swapExactOutput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {});
            });

            describe("when a path contains not allowed token", () => {});
        });
    });

    describe("#supportsInterface", () => {
        describe("returns `true` on IChiefTrader", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `true` on ITrader", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `true` on ERC165", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `false` on `0x`", async () => {
            it("returns `false`", async () => {});
        });
    });
});
