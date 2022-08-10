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
} from "../library/Helpers";
import Exceptions from "../library/Exceptions";
import {
    DelayedProtocolParamsStruct,
    PerpVaultGovernance,
} from "../types/PerpVaultGovernance";
import { REGISTER_VAULT } from "../library/PermissionIdsLibrary";
import { contract } from "../library/setup";
import { address } from "../library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, integer, tuple } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "../behaviors/vaultGovernance";
import { InternalParamsStruct } from "../types/IVaultGovernance";
import { ContractMetaBehaviour } from "../behaviors/contractMeta";
import { AAVE_VAULT_GOVERNANCE_INTERFACE_ID } from "../library/Constants";
import { randomBytes } from "crypto";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

type DeployOptions = {
    internalParams?: InternalParamsStruct;
    skipInit?: boolean;
};

contract<PerpVaultGovernance, DeployOptions, CustomContext>(
    "Optimism__PerpVaultGovernance",
    function () {
        before(async () => {
            const perpVaultAddress = (await getNamedAccounts())
                .perpVault;
            const clearingHouseAddress = (await getNamedAccounts())
                .clearingHouse;
            const accountBalanceAddress = (await getNamedAccounts())
                .accountBalance;
            const vusdcAddress = (await
                getNamedAccounts()).vusdcAddress;
            const usdcAddress = (await
                getNamedAccounts()).usdc;
            const uniV3FactoryAddress = (await
                getNamedAccounts()).uniswapV3Factory;
            const veth = (await getNamedAccounts()).vethAddress;

            this.params = {
                vault: perpVaultAddress,
                clearingHouse: clearingHouseAddress,
                accountBalance: accountBalanceAddress,
                vusdcAddress: vusdcAddress,
                usdcAddress: usdcAddress,
                uniV3FactoryAddress: uniV3FactoryAddress,
                maxProtocolLeverage: 10
            };
            

            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();

                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton: this.perpVaultSingleton.address,
                        },
                        skipInit = false,
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "PerpVaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "PerpVaultGovernance",
                            args: [
                                internalParams,
                                this.params,
                            ],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "PerpVaultGovernance",
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
                            veth,
                            5,
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
            tuple(address, address, address, address, address, address, integer()).map(
                ([vault, clearingHouse, accountBalance, vusdcAddress, usdcAddress, uniV3FactoryAddress, x]) => ({
                    vault,
                    clearingHouse,
                    accountBalance,
                    vusdcAddress,
                    usdcAddress,
                    uniV3FactoryAddress,
                    maxProtocolLeverage: x,
                })
            );

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });

            describe("contract with real parameters", () => {
                it ("goes okay", async () => {
                    await deployments.fixture();
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton:
                                        this.aaveVaultSingleton.address,
                                },
                                this.params
                            ],
                            autoMine: true,
                        })
                    ).not.to.be.reverted;
                })
            })

            describe("edge cases", () => {
                describe("when perpVault address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        let params = this.params;
                        params.vault = ethers.constants.AddressZero;
                        await expect(
                            deployments.deploy("PerpVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    params
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when clearingHouse address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        let params = this.params;
                        params.clearingHouse = ethers.constants.AddressZero;
                        await expect(
                            deployments.deploy("PerpVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    params
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when accountBalance address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        let params = this.params;
                        params.accountBalance = ethers.constants.AddressZero;
                        await expect(
                            deployments.deploy("PerpVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    params
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when vusdc address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        let params = this.params;
                        params.vusdcAddress = ethers.constants.AddressZero;
                        await expect(
                            deployments.deploy("PerpVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    params
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when usdc address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        let params = this.params;
                        params.usdcAddress = ethers.constants.AddressZero;
                        await expect(
                            deployments.deploy("PerpVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    params
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when uniV3Factory address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        let params = this.params;
                        params.uniV3FactoryAddress = ethers.constants.AddressZero;
                        await expect(
                            deployments.deploy("PerpVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.aaveVaultSingleton.address,
                                    },
                                    params
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });
/*
        describe("#stageDelayedProtocolParams", () => {
            describe("edge cases", () => {
                describe("when estimated Aave APY is larger than limit", () => {
                    it("reverts", async () => {
                        const lendingPoolAddress = (await getNamedAccounts())
                            .aaveLendingPool;
                        const maxEstimatedAaveAPY =
                            await this.aaveVaultGovernance.MAX_ESTIMATED_AAVE_APY();
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageDelayedProtocolParams({
                                    lendingPool: lendingPoolAddress,
                                    estimatedAaveAPY:
                                        maxEstimatedAaveAPY.add(1),
                                })
                        ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                    });
                });
            });
        });
        */
/*
        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${AAVE_VAULT_GOVERNANCE_INTERFACE_ID} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        AAVE_VAULT_GOVERNANCE_INTERFACE_ID
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
            ...this,
        });

        ContractMetaBehaviour.call(this, {
            contractName: "AaveVaultGovernance",
            contractVersion: "1.0.0",
        });
*/
    }
);
