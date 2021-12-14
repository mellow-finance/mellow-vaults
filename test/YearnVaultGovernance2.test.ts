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

    // describe("#stagedDelayedProtocolParams", () => {
    //     const someParams: DelayedProtocolParamsStruct = {
    //         yearnVaultRegistry: randomAddress(),
    //     };

    //     const noneParams: DelayedProtocolParamsStruct = {
    //         yearnVaultRegistry: ethers.constants.AddressZero,
    //     };

    //     pit(
    //         "always equals to params that were just staged",
    //         { numRuns: 20 },
    //         address,
    //         async (yearnVaultRegistryAddress: string) => {
    //             const params: DelayedProtocolParamsStruct = {
    //                 yearnVaultRegistry: yearnVaultRegistryAddress,
    //             };
    //             await this.subject
    //                 .connect(this.admin)
    //                 .stageDelayedProtocolParams(params);
    //             const actualParams =
    //                 await this.subject.stagedDelayedProtocolParams();

    //             return equals(toObject(actualParams), params);
    //         }
    //     );

    //     it("returns delayed protocol params staged for commit", async () => {
    //         await this.subject
    //             .connect(this.admin)
    //             .stageDelayedProtocolParams(someParams);
    //         const actualParams =
    //             await this.subject.stagedDelayedProtocolParams();
    //         expect(actualParams).to.be.equivalent(someParams);
    //     });

    //     describe("when no params are staged for commit", () => {
    //         it("returns zero struct", async () => {
    //             const actualParams =
    //                 await this.subject.stagedDelayedProtocolParams();
    //             expect(actualParams).to.equivalent(noneParams);
    //         });
    //     });

    //     describe("when params were just committed", () => {
    //         it("returns zero struct", async () => {
    //             await this.subject
    //                 .connect(this.admin)
    //                 .stageDelayedProtocolParams(someParams);
    //             await sleep(this.governanceDelay);
    //             await this.subject
    //                 .connect(this.admin)
    //                 .commitDelayedProtocolParams();
    //             const actualParams =
    //                 await this.subject.stagedDelayedProtocolParams();
    //             expect(actualParams).to.equivalent(noneParams);
    //         });
    //     });
    // });

    // describe("#delayedProtocolParams", () => {
    //     const someParams: DelayedProtocolParamsStruct = {
    //         yearnVaultRegistry: randomAddress(),
    //     };

    //     const noneParams: DelayedProtocolParamsStruct = {
    //         yearnVaultRegistry: ethers.constants.AddressZero,
    //     };

    //     pit(
    //         "just staging params doesn't affect delayedProtocolParams",
    //         { numRuns: 20 },
    //         address,
    //         async (yearnVaultRegistryAddress: string) => {
    //             const params: DelayedProtocolParamsStruct = {
    //                 yearnVaultRegistry: yearnVaultRegistryAddress,
    //             };
    //             await this.subject
    //                 .connect(this.admin)
    //                 .stageDelayedProtocolParams(params);
    //             const actualParams = await this.subject.delayedProtocolParams();

    //             return !equals(toObject(actualParams), params);
    //         }
    //     );

    //     it("returns current delayed protocol params", async () => {
    //         await this.subject
    //             .connect(this.admin)
    //             .stageDelayedProtocolParams(someParams);
    //         await sleep(this.governanceDelay);
    //         await this.subject
    //             .connect(this.admin)
    //             .commitDelayedProtocolParams();
    //         const actualParams = await this.subject.delayedProtocolParams();
    //         expect(actualParams).to.equivalent(someParams);
    //     });

    //     describe("when no params were committed", () => {
    //         it("returns non-zero params initialized in constructor", async () => {
    //             const actualParams = await this.subject.delayedProtocolParams();
    //             expect(actualParams).to.not.be.equivalent(noneParams);
    //         });
    //     });
    // });

    // describe("#stageDelayedProtocolParams", () => {
    //     const paramsToStage: DelayedProtocolParamsStruct = {
    //         yearnVaultRegistry: randomAddress(),
    //     };

    //     describe("when happy case", () => {
    //         beforeEach(async () => {
    //             await deployments.execute(
    //                 "YearnVaultGovernance",
    //                 { from: admin, autoMine: true },
    //                 "stageDelayedProtocolParams",
    //                 paramsToStage
    //             );
    //         });
    //         it("stages new delayed protocol params", async () => {
    //             const stagedParams = await deployments.read(
    //                 "YearnVaultGovernance",
    //                 "stagedDelayedProtocolParams"
    //             );
    //             expect(toObject(stagedParams)).to.eql(paramsToStage);
    //         });

    //         it("sets the delay for commit", async () => {
    //             const governanceDelay = await deployments.read(
    //                 "ProtocolGovernance",
    //                 "governanceDelay"
    //             );
    //             const timestamp = await deployments.read(
    //                 "YearnVaultGovernance",
    //                 "delayedProtocolParamsTimestamp"
    //             );
    //             expect(timestamp).to.eq(
    //                 governanceDelay.add(startTimestamp).add(1)
    //             );
    //         });
    //     });

    //     describe("when called not by protocol admin", () => {
    //         it("reverts", async () => {
    //             for (const actor of [deployer, stranger]) {
    //                 await expect(
    //                     deployments.execute(
    //                         "YearnVaultGovernance",
    //                         { from: actor, autoMine: true },
    //                         "stageDelayedProtocolParams",
    //                         paramsToStage
    //                     )
    //                 ).to.be.revertedWith(Exceptions.ADMIN);
    //             }
    //         });
    //     });
    // });

    // describe("#commitDelayedProtocolParams", () => {
    //     const paramsToCommit: DelayedProtocolParamsStruct = {
    //         yearnVaultRegistry: randomAddress(),
    //     };

    //     describe("when happy case", () => {
    //         beforeEach(async () => {
    //             await deployments.execute(
    //                 "YearnVaultGovernance",
    //                 { from: admin, autoMine: true },
    //                 "stageDelayedProtocolParams",
    //                 paramsToCommit
    //             );
    //             const governanceDelay = await deployments.read(
    //                 "ProtocolGovernance",
    //                 "governanceDelay"
    //             );
    //             await sleep(governanceDelay);
    //             await deployments.execute(
    //                 "YearnVaultGovernance",
    //                 { from: admin, autoMine: true },
    //                 "commitDelayedProtocolParams"
    //             );
    //         });
    //         it("commits staged protocol params", async () => {
    //             const protocolParams = await deployments.read(
    //                 "YearnVaultGovernance",
    //                 "delayedProtocolParams"
    //             );
    //             expect(toObject(protocolParams)).to.eql(paramsToCommit);
    //         });
    //         it("resets staged protocol params", async () => {
    //             const stagedProtocolParams = await deployments.read(
    //                 "YearnVaultGovernance",
    //                 "stagedDelayedProtocolParams"
    //             );
    //             expect(toObject(stagedProtocolParams)).to.eql({
    //                 yearnVaultRegistry: ethers.constants.AddressZero,
    //             });
    //         });
    //         it("resets staged protocol params timestamp", async () => {
    //             const stagedProtocolParams = await deployments.read(
    //                 "YearnVaultGovernance",
    //                 "delayedProtocolParamsTimestamp"
    //             );
    //             expect(toObject(stagedProtocolParams)).to.eq(0);
    //         });
    //     });

    //     describe("when called not by admin", () => {
    //         it("reverts", async () => {
    //             await deployments.execute(
    //                 "YearnVaultGovernance",
    //                 { from: admin, autoMine: true },
    //                 "stageDelayedProtocolParams",
    //                 paramsToCommit
    //             );
    //             const governanceDelay = await deployments.read(
    //                 "ProtocolGovernance",
    //                 "governanceDelay"
    //             );
    //             await sleep(governanceDelay);

    //             for (const actor of [deployer, stranger]) {
    //                 await expect(
    //                     deployments.execute(
    //                         "YearnVaultGovernance",
    //                         { from: actor, autoMine: true },
    //                         "stageDelayedProtocolParams",
    //                         paramsToCommit
    //                     )
    //                 ).to.be.revertedWith(Exceptions.ADMIN);
    //             }
    //         });
    //     });

    //     describe("when time before delay has not elapsed", () => {
    //         it("reverts", async () => {
    //             await deployments.execute(
    //                 "YearnVaultGovernance",
    //                 { from: admin, autoMine: true },
    //                 "stageDelayedProtocolParams",
    //                 paramsToCommit
    //             );
    //             // immediate execution
    //             await expect(
    //                 deployments.execute(
    //                     "YearnVaultGovernance",
    //                     { from: admin, autoMine: true },
    //                     "commitDelayedProtocolParams"
    //                 )
    //             ).to.be.revertedWith(Exceptions.TIMESTAMP);

    //             const governanceDelay = await deployments.read(
    //                 "ProtocolGovernance",
    //                 "governanceDelay"
    //             );
    //             await sleep(governanceDelay.sub(15));
    //             // execution 15 seconds before the deadline
    //             await expect(
    //                 deployments.execute(
    //                     "YearnVaultGovernance",
    //                     { from: admin, autoMine: true },
    //                     "commitDelayedProtocolParams"
    //                 )
    //             ).to.be.revertedWith(Exceptions.TIMESTAMP);
    //         });
    //     });
    // });

    // describe("#yTokenForToken", () => {
    //     const YEARN_WETH_POOL =
    //         "0xa258C4606Ca8206D8aA700cE2143D7db854D168c".toLowerCase();
    //     it("returns a corresponding yVault for token", async () => {
    //         const { read } = deployments;
    //         const { weth } = await getNamedAccounts();
    //         const yToken = await read(
    //             "YearnVaultGovernance",
    //             "yTokenForToken",
    //             weth
    //         );
    //         expect(yToken.toLowerCase()).to.eq(YEARN_WETH_POOL);
    //     });

    //     describe("when overriden by setYTokenForToken", () => {
    //         it("returns overriden yToken", async () => {
    //             const { read } = deployments;
    //             const { weth, admin } = await getNamedAccounts();
    //             const newYToken = randomAddress();
    //             await withSigner(admin, async (s) => {
    //                 const g = await (
    //                     await ethers.getContract("YearnVaultGovernance")
    //                 ).connect(s);
    //                 await g.setYTokenForToken(weth, newYToken);
    //             });
    //             const yToken = await read(
    //                 "YearnVaultGovernance",
    //                 "yTokenForToken",
    //                 weth
    //             );
    //             expect(yToken.toLowerCase()).to.eq(newYToken.toLowerCase());
    //         });
    //     });

    //     describe("when yToken doesn't exist in overrides or yearnRegistry", () => {
    //         it("returns 0 address", async () => {
    //             const { read } = deployments;
    //             const yToken = await read(
    //                 "YearnVaultGovernance",
    //                 "yTokenForToken",
    //                 randomAddress()
    //             );
    //             expect(yToken).to.eq(ethers.constants.AddressZero);
    //         });
    //     });
    // });

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
