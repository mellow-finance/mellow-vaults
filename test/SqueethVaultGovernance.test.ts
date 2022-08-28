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
    SqueethVaultGovernance,
} from "./types/SqueethVaultGovernance";
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import { contract } from "./library/setup";
import { address } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, integer, tuple } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStruct } from "./types/IVaultGovernance";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";
import { SQUEETH_VAULT_GOVERNANCE_INTERFACE_ID } from "./library/Constants";
import { randomBytes } from "crypto";
import { Signer } from "ethers";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

type DeployOptions = {
    internalParams?: InternalParamsStruct;
    controller?: string;
    router?: string;
    skipInit?: boolean;
};

contract<SqueethVaultGovernance, DeployOptions, CustomContext>(
    "SqueethVaultGovernance",
    function () {
        before(async () => {
            const { squeethController, uniswapV3Router } =
                await getNamedAccounts();
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();

                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton: this.squeethVaultSingleton.address,
                        },
                        controller = squeethController,
                        router = uniswapV3Router,
                        skipInit = false,
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "SqueethVaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "SqueethVaultGovernance",
                            args: [
                                internalParams,
                                {
                                    controller,
                                    router,
                                },
                            ],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "SqueethVaultGovernance",
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
                            this.ownerSigner.address,
                            true
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
            tuple(address, address).map(([controller, router]) => ({
                controller,
                router,
            }));

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });

            describe("edge cases", () => {
                describe("when controller address is 0", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        await deployments.fixture();
                        const { uniswapV3Router } = await getNamedAccounts();
                        await expect(
                            deployments.deploy("SqueethVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.squeethVaultSingleton.address,
                                    },
                                    {
                                        controller:
                                            ethers.constants.AddressZero,
                                        router: uniswapV3Router,
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when router address is 0", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        await deployments.fixture();
                        const { squeethController } = await getNamedAccounts();
                        await expect(
                            deployments.deploy("SqueethVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.squeethVaultSingleton.address,
                                    },
                                    {
                                        controller: squeethController,
                                        router: ethers.constants.AddressZero,
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#stageDelayedProtocolParams", () => {
            describe("edge cases", () => {
                describe("when controller address is 0", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        const uniswapV3Router = (await getNamedAccounts())
                            .uniswapV3Router;
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageDelayedProtocolParams({
                                    controller: ethers.constants.AddressZero,
                                    router: uniswapV3Router,
                                })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });

                describe("when router address is 0", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        const squeethController = (await getNamedAccounts())
                            .squeethController;
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageDelayedProtocolParams({
                                    controller: squeethController,
                                    router: ethers.constants.AddressZero,
                                })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${SQUEETH_VAULT_GOVERNANCE_INTERFACE_ID} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        SQUEETH_VAULT_GOVERNANCE_INTERFACE_ID
                    )
                ).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .supportsInterface(randomBytes(4))
                        ).to.not.be.reverted;
                    });
                });
            });
        });

        vaultGovernanceBehavior.call(this, {
            delayedProtocolParams,
            defaultCreateVault: async (
                deployer: Signer,
                tokenAddresses: string[],
                owner: string
            ) => {
                await this.subject.connect(deployer).createVault(owner, true);
            },
            ...this,
        });

        ContractMetaBehaviour.call(this, {
            contractName: "SqueethVaultGovernance",
            contractVersion: "1.0.0",
        });
    }
);
