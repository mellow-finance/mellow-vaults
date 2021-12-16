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
    AaveVaultGovernance,
} from "./types/AaveVaultGovernance";
import { setupDefaultContext, TestContext } from "./library/setup";
import { Context, Suite } from "mocha";
import { equals } from "ramda";
import { address, pit } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import {
    InternalParamsStruct,
    InternalParamsStructOutput,
} from "./types/IVaultGovernance";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

type DeployOptions = {
    internalParams?: InternalParamsStructOutput;
    lendingPool?: string;
    skipInit?: boolean;
};

// @ts-ignore
describe("AaveVaultGovernance", function (this: TestContext<
    AaveVaultGovernance,
    DeployOptions
> &
    CustomContext) {
    before(async () => {
        // @ts-ignore
        await setupDefaultContext.call(this);
        const lendingPoolAddress = (await getNamedAccounts()).aaveLendingPool;
        this.deploymentFixture = deployments.createFixture(
            async (_, options?: DeployOptions) => {
                await deployments.fixture();
                const {
                    internalParams = {
                        protocolGovernance: this.protocolGovernance.address,
                        registry: this.vaultRegistry.address,
                    },
                    lendingPool = lendingPoolAddress,
                    skipInit = false,
                } = options || {};
                const { address } = await deployments.deploy(
                    "AaveVaultGovernanceTest",
                    {
                        from: this.deployer.address,
                        contract: "AaveVaultGovernance",
                        args: [internalParams, { lendingPool }],
                        autoMine: true,
                    }
                );
                this.subject = await ethers.getContractAt(
                    "AaveVaultGovernance",
                    address
                );
                this.ownerSigner = await addSigner(randomAddress());
                this.strategySigner = await addSigner(randomAddress());

                if (!skipInit) {
                    const { address: factoryAddress } =
                        await deployments.deploy("AaveVaultFactoryTest", {
                            from: this.deployer.address,
                            contract: "AaveVaultFactory",
                            args: [this.subject.address],
                            autoMine: true,
                        });
                    await this.subject.initialize(factoryAddress);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .setPendingVaultGovernancesAdd([this.subject.address]);
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitVaultGovernancesAdd();
                    await this.subject.deployVault(
                        this.tokens.map((x: any) => x.address),
                        [],
                        this.ownerSigner.address
                    );
                    this.nft = (
                        await this.vaultRegistry.vaultsCount()
                    ).toNumber();
                    await this.vaultRegistry
                        .connect(this.ownerSigner)
                        .approve(this.strategySigner.address, this.nft);
                }
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
        this.startTimestamp = now();
        await sleepTo(this.startTimestamp);
    });

    const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> =
        address.map((lendingPool) => ({ lendingPool }));

    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(ethers.constants.AddressZero).to.not.eq(
                this.subject.address
            );
        });

        describe("edge cases", () => {
            describe("when lendingPool address is 0", () => {
                it("reverts", async () => {
                    await deployments.fixture();
                    await expect(
                        deployments.deploy("AaveVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                },
                                {
                                    lendingPool: ethers.constants.AddressZero,
                                },
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(
                        Exceptions.AAVE_LENDING_POOL_ADDRESS_ZERO
                    );
                });
            });
        });
    });

    // @ts-ignore
    vaultGovernanceBehavior.call(this, {
        delayedProtocolParams,
        ...this,
    });
});
