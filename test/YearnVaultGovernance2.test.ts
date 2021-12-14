import { Assertion, expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    toObject,
    withSigner,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import {
    DelayedProtocolParamsStruct,
    YearnVaultGovernance,
} from "./types/YearnVaultGovernance";
import { setupDefaultContext, TestContext } from "./library/setup";
import { Context, Suite } from "mocha";
import { equals } from "ramda";
import { address, pit } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

// @ts-ignore
describe("YearnVaultGovernance2", function (this: TestContext<YearnVaultGovernance> &
    CustomContext) {
    before(async () => {
        await setupDefaultContext.call(this);
        const yearnVaultRegistryAddress = (await getNamedAccounts())
            .yearnVaultRegistry;
        this.deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            const { address } = await deployments.deploy(
                "YearnVaultGovernance",
                {
                    from: this.deployer.address,
                    args: [
                        {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                        },
                        { yearnVaultRegistry: yearnVaultRegistryAddress },
                    ],
                    autoMine: true,
                }
            );
            this.subject = await ethers.getContractAt(
                "YearnVaultGovernance",
                address
            );
            this.ownerSigner = await addSigner(randomAddress());
            this.strategySigner = await addSigner(randomAddress());
            await this.subject.deployVault(
                this.tokens.map((x) => x.address),
                [],
                this.ownerSigner.address
            );
            this.nft = (await this.vaultRegistry.vaultsCount()).toNumber();
            await this.vaultRegistry
                .connect(this.ownerSigner)
                .approve(this.strategySigner.address, this.nft);
        });
    });

    beforeEach(async () => {
        await this.deploymentFixture();
        this.startTimestamp = now();
        await sleepTo(this.startTimestamp);
    });

    const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> =
        address.map((yearnVaultRegistry) => ({ yearnVaultRegistry }));

    vaultGovernanceBehavior.call(this, {
        delayedProtocolParams,
        ...this,
    });

    describe("#yTokenForToken", () => {
        const YEARN_WETH_POOL = "0xa258C4606Ca8206D8aA700cE2143D7db854D168c";

        it("returns yToken (yVault) in yToken overrides (set by #setYTokenForToken) or corresponding to ERC20 token in YearnVaultRegistry", async () => {
            const yToken = await this.subject.yTokenForToken(this.weth.address);
            expect(YEARN_WETH_POOL).to.eq(yToken);
        });

        describe("access list", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .yTokenForToken(this.weth.address)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when yToken doesn't exist in overrides or YearnVaultRegistry", () => {
                it("returns 0", async () => {
                    const tokenAddress = randomAddress();
                    expect(ethers.constants.AddressZero).to.eq(
                        await this.subject.yTokenForToken(tokenAddress)
                    );
                });
            });

            describe("when yToken was not overridden by #setYTokenForToken", () => {
                it("returns token from YearnVaultRegistry", async () => {
                    const yToken = await this.subject.yTokenForToken(
                        this.weth.address
                    );
                    expect(YEARN_WETH_POOL).to.eq(yToken);
                });
            });

            describe("when yToken was overridden by #setYTokenForToken", () => {
                it("returns overridden token", async () => {
                    const yTokenAddress = randomAddress();
                    await this.subject
                        .connect(this.admin)
                        .setYTokenForToken(this.weth.address, yTokenAddress);
                    expect(yTokenAddress).to.eq(
                        await this.subject.yTokenForToken(this.weth.address)
                    );
                });
            });
        });
        // it("returns a corresponding yVault for token", async () => {
        //     const { read } = deployments;
        //     const { weth } = await getNamedAccounts();
        //     const yToken = await read(
        //         "YearnVaultGovernance",
        //         "yTokenForToken",
        //         weth
        //     );
        //     expect(yToken.toLowerCase()).to.eq(YEARN_WETH_POOL);
        // });

        // describe("when overriden by setYTokenForToken", () => {
        //     it("returns overriden yToken", async () => {
        //         const { read } = deployments;
        //         const { weth, admin } = await getNamedAccounts();
        //         const newYToken = randomAddress();
        //         await withSigner(admin, async (s) => {
        //             const g = await (
        //                 await ethers.getContract("YearnVaultGovernance")
        //             ).connect(s);
        //             await g.setYTokenForToken(weth, newYToken);
        //         });
        //         const yToken = await read(
        //             "YearnVaultGovernance",
        //             "yTokenForToken",
        //             weth
        //         );
        //         expect(yToken.toLowerCase()).to.eq(newYToken.toLowerCase());
        //     });
        // });

        // describe("when yToken doesn't exist in overrides or yearnRegistry", () => {
        //     it("returns 0 address", async () => {
        //         const { read } = deployments;
        //         const yToken = await read(
        //             "YearnVaultGovernance",
        //             "yTokenForToken",
        //             randomAddress()
        //         );
        //         expect(yToken).to.eq(ethers.constants.AddressZero);
        //     });
        // });
    });

    // describe("setYTokenForToken", () => {
    //     it("sets a yToken override for a token", async () => {
    //         const { read } = deployments;
    //         const { weth, admin } = await getNamedAccounts();
    //         const newYToken = randomAddress();
    //         await withSigner(admin, async (s) => {
    //             const g = (
    //                 await ethers.getContract("YearnVaultGovernance")
    //             ).connect(s);
    //             await g.setYTokenForToken(weth, newYToken);
    //         });
    //         const yToken = await read(
    //             "YearnVaultGovernance",
    //             "yTokenForToken",
    //             weth
    //         );
    //         expect(yToken.toLowerCase()).to.eq(newYToken.toLowerCase());
    //     });

    //     describe("when called not by admin", () => {
    //         it("reverts", async () => {
    //             const { weth, stranger, deployer } = await getNamedAccounts();
    //             for (const actor of [stranger, deployer]) {
    //                 await withSigner(actor, async (s) => {
    //                     const g = (
    //                         await ethers.getContract("YearnVaultGovernance")
    //                     ).connect(s);
    //                     await expect(
    //                         g.setYTokenForToken(weth, randomAddress())
    //                     ).to.be.revertedWith(Exceptions.ADMIN);
    //                 });
    //             }
    //         });
    //     });
    // });
});
