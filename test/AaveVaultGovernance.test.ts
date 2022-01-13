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
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import { contract } from "./library/setup";
import { address } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, integer, tuple } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStruct } from "./types/IVaultGovernance";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

type DeployOptions = {
    internalParams?: InternalParamsStruct;
    lendingPool?: string;
    skipInit?: boolean;
};

contract<AaveVaultGovernance, DeployOptions, CustomContext>(
    "AaveVaultGovernance",
    function () {
        before(async () => {
            const lendingPoolAddress = (await getNamedAccounts())
                .aaveLendingPool;
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();

                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton: this.aaveVaultSingleton.address,
                        },
                        lendingPool = lendingPoolAddress,
                        skipInit = false,
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "AaveVaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "AaveVaultGovernance",
                            args: [
                                internalParams,
                                {
                                    lendingPool,
                                    estimatedAaveAPYX96:
                                        BigNumber.from(2).pow(98),
                                },
                            ],
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
                        await this.protocolGovernance
                            .connect(this.admin)
                            .stagePermissionGrants(this.subject.address, [
                                REGISTER_VAULT,
                            ]);
                        await sleep(this.governanceDelay);
                        await this.protocolGovernance
                            .connect(this.admin)
                            .commitPermissionGrants(this.subject.address);
                        this.nft =
                            (
                                await this.vaultRegistry.vaultsCount()
                            ).toNumber() + 1;

                        await this.subject.createVault(
                            this.tokens.map((x: any) => x.address),
                            this.ownerSigner.address
                        );
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
            tuple(address, integer({ min: 1, max: 2 ** 6 })).map(
                ([lendingPool, num]) => ({
                    lendingPool,
                    estimatedAaveAPYX96: BigNumber.from(num).mul(
                        BigNumber.from(2).pow(94)
                    ),
                })
            );

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
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    {
                                        lendingPool:
                                            ethers.constants.AddressZero,
                                        estimatedAaveAPYX96:
                                            BigNumber.from(2).pow(98),
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when estimatedAaveAPYX96 is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        const lendingPoolAddress = (await getNamedAccounts())
                            .aaveLendingPool;
                        await expect(
                            deployments.deploy("AaveVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    {
                                        lendingPool: lendingPoolAddress,
                                        estimatedAaveAPYX96: 0,
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                    });
                });
            });
        });

        vaultGovernanceBehavior.call(this, {
            delayedProtocolParams,
            ...this,
        });
    }
);
