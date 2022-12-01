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
import { address, uint256, uint8, uint8Number } from "./library/property";
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
            const {
                squeethController,
                uniswapV3Router,
                squeethWethBorrowPool,
            } = await getNamedAccounts();
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

                    this.helper = await ethers.getContract("SqueethHelper");
                    let mellowOracle = await ethers.getContract(
                        "SqueethHelper"
                    );

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
                                    slippageD9: BigNumber.from(10).pow(7),
                                    twapPeriod: BigNumber.from(420),
                                    wethBorrowPool: squeethWethBorrowPool,
                                    oracle: mellowOracle.address,
                                    squeethHelper: this.helper.address,
                                    maxDepegD9: BigNumber.from(10)
                                        .pow(7)
                                        .mul(20),
                                },
                            ],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "SqueethVaultGovernance",
                        address
                    );
                    this.protocolParams =
                        await this.subject.delayedProtocolParams();
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
            tuple(
                address,
                address,
                uint256,
                uint8Number,
                address,
                address,
                address,
                uint256
            ).map(
                ([
                    controller,
                    router,
                    slippageD9,
                    twapPeriod,
                    wethBorrowPool,
                    oracle,
                    squeethHelper,
                    maxDepegD9,
                ]) => ({
                    controller,
                    router,
                    slippageD9,
                    twapPeriod,
                    wethBorrowPool,
                    oracle,
                    squeethHelper,
                    maxDepegD9,
                })
            );

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });

            describe("edge cases", () => {
                describe("when controller address is 0", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        console.log("params: ");
                        console.log(this.protocolParams);
                        await deployments.fixture();

                        console.log("params: ");
                        console.log(this.protocolParams);
                        console.log("router: " + this.protocolParams.router);
                        console.log("router: " + this.protocolParams["router"]);
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
                                        router: this.protocolParams.router,
                                        slippageD9:
                                            this.protocolParams.slippageD9,
                                        twapPeriod:
                                            this.protocolParams.twapPeriod,
                                        wethBorrowPool:
                                            this.protocolParams.wethBorrowPool,
                                        oracle: this.protocolParams.oracle,
                                        squeethHelper:
                                            this.protocolParams.squeethHelper,
                                        maxDepegD9:
                                            this.protocolParams.maxDepegD9,
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
                                            this.protocolParams.controller,
                                        router: ethers.constants.AddressZero,
                                        slippageD9:
                                            this.protocolParams.slippageD9,
                                        twapPeriod:
                                            this.protocolParams.twapPeriod,
                                        wethBorrowPool:
                                            this.protocolParams.wethBorrowPool,
                                        oracle: this.protocolParams.oracle,
                                        squeethHelper:
                                            this.protocolParams.squeethHelper,
                                        maxDepegD9:
                                            this.protocolParams.maxDepegD9,
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
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageDelayedProtocolParams({
                                    controller: ethers.constants.AddressZero,
                                    router: this.protocolParams.router,
                                    slippageD9: this.protocolParams.slippageD9,
                                    twapPeriod: this.protocolParams.twapPeriod,
                                    wethBorrowPool:
                                        this.protocolParams.wethBorrowPool,
                                    oracle: this.protocolParams.oracle,
                                    squeethHelper:
                                        this.protocolParams.squeethHelper,
                                    maxDepegD9: this.protocolParams.maxDepegD9,
                                })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });

                describe("when router address is 0", () => {
                    it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageDelayedProtocolParams({
                                    controller: this.protocolParams.controller,
                                    router: ethers.constants.AddressZero,
                                    slippageD9: this.protocolParams.slippageD9,
                                    twapPeriod: this.protocolParams.twapPeriod,
                                    wethBorrowPool:
                                        this.protocolParams.wethBorrowPool,
                                    oracle: this.protocolParams.oracle,
                                    squeethHelper:
                                        this.protocolParams.squeethHelper,
                                    maxDepegD9: this.protocolParams.maxDepegD9,
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
                await this.subject.connect(deployer).createVault(owner);
            },
            ...this,
        });

        ContractMetaBehaviour.call(this, {
            contractName: "SqueethVaultGovernance",
            contractVersion: "1.0.0",
        });
    }
);
