import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
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
import { Arbitrary, integer, tuple } from "fast-check";
import { BigNumber } from "@ethersproject/bignumber";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "../behaviors/vaultGovernance";
import { InternalParamsStruct } from "../types/IVaultGovernance";
import { ContractMetaBehaviour } from "../behaviors/contractMeta";
import { PERP_VAULT_GOVERNANCE_INTERFACE_ID } from "../library/Constants";
import { randomBytes } from "crypto";

import { abi as IPerpInternalVault } from "../../test/helpers/PerpVaultABI.json";
import { abi as IClearingHouse } from "../../test/helpers/ClearingHouseABI.json";
import { abi as IAccountBalance } from "../../test/helpers/AccountBalanceABI.json";

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
            const perpVaultAddress = (await getNamedAccounts()).perpVault;
            const clearingHouseAddress = (await getNamedAccounts())
                .clearingHouse;
            const accountBalanceAddress = (await getNamedAccounts())
                .accountBalance;
            const vusdcAddress = (await getNamedAccounts()).vusdcAddress;
            const usdcAddress = (await getNamedAccounts()).usdc;
            const uniV3FactoryAddress = (await getNamedAccounts())
                .uniswapV3Factory;
            const veth = (await getNamedAccounts()).vethAddress;

            this.governanceProtocolParams = {
                vault: perpVaultAddress,
                clearingHouse: clearingHouseAddress,
                accountBalance: accountBalanceAddress,
                vusdcAddress: vusdcAddress,
                usdcAddress: usdcAddress,
                uniV3FactoryAddress: uniV3FactoryAddress,
                maxProtocolLeverage: 10,
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
                                this.governanceProtocolParams,
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

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });

            describe("contract with real parameters", () => {
                it("goes okay", async () => {
                    await deployments.fixture();
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton: this.perpVaultSingleton.address,
                                },
                                this.governanceProtocolParams,
                            ],
                            autoMine: true,
                        })
                    ).not.to.be.reverted;
                });
            });
        });

        describe("#parameters checks", () => {
            describe("perpVault", () => {
                it("reverts when address zero in constructor", async () => {
                    await deployments.fixture();
                    const address = this.governanceProtocolParams.vault;
                    this.governanceProtocolParams.vault =
                        ethers.constants.AddressZero;
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton: this.perpVaultSingleton.address,
                                },
                                this.governanceProtocolParams,
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.vault = address;
                });

                it("works as expected in parameters change", async () => {
                    const address = this.governanceProtocolParams.vault;
                    this.governanceProtocolParams.vault =
                        ethers.constants.AddressZero;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.vault = address;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).not.to.be.reverted;
                });

                it("contract exists", async () => {
                    const perpInternalVault = await ethers.getContractAt(
                        IPerpInternalVault,
                        this.governanceProtocolParams.vault
                    );
                    const address =
                        await perpInternalVault.getSettlementToken();
                    expect(address).to.be.eq(
                        this.governanceProtocolParams.usdcAddress
                    );
                });
            });
            describe("clearingHouse", () => {
                it("reverts when address zero, works as expected as a parameter", async () => {
                    await deployments.fixture();
                    const address = this.governanceProtocolParams.clearingHouse;
                    this.governanceProtocolParams.clearingHouse =
                        ethers.constants.AddressZero;
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton: this.perpVaultSingleton.address,
                                },
                                this.governanceProtocolParams,
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.clearingHouse = address;
                });
                it("works as expected in parameters change", async () => {
                    const address = this.governanceProtocolParams.clearingHouse;
                    this.governanceProtocolParams.clearingHouse =
                        ethers.constants.AddressZero;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.clearingHouse = address;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).not.to.be.reverted;
                });
                it("contract exists", async () => {
                    const clearingHouse = await ethers.getContractAt(
                        IClearingHouse,
                        this.governanceProtocolParams.clearingHouse
                    );
                    const factory = await clearingHouse.getUniswapV3Factory();
                    expect(factory).to.be.eq(
                        this.governanceProtocolParams.uniV3FactoryAddress
                    );
                });
            });
            describe("accountBalance", () => {
                it("reverts when address zero, works as expected as a parameter", async () => {
                    await deployments.fixture();
                    const address =
                        this.governanceProtocolParams.accountBalance;
                    this.governanceProtocolParams.accountBalance =
                        ethers.constants.AddressZero;
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton: this.perpVaultSingleton.address,
                                },
                                this.governanceProtocolParams,
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.accountBalance = address;
                });
                it("works as expected in parameters change", async () => {
                    const address =
                        this.governanceProtocolParams.accountBalance;
                    this.governanceProtocolParams.accountBalance =
                        ethers.constants.AddressZero;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.accountBalance = address;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).not.to.be.reverted;
                });
                it("contract exists", async () => {
                    const { vethAddress } = await getNamedAccounts();

                    const accountBalance = await ethers.getContractAt(
                        IAccountBalance,
                        this.governanceProtocolParams.accountBalance
                    );
                    const amount = await accountBalance.getTotalPositionSize(
                        this.deployer.address,
                        vethAddress
                    );
                    expect(amount).to.be.eq(0);
                });
            });
            describe("vUsd", () => {
                it("reverts when address zero, works as expected as a parameter", async () => {
                    await deployments.fixture();
                    const address = this.governanceProtocolParams.vusdcAddress;
                    this.governanceProtocolParams.vusdcAddress =
                        ethers.constants.AddressZero;
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton: this.perpVaultSingleton.address,
                                },
                                this.governanceProtocolParams,
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.vusdcAddress = address;
                });
                it("works as expected in parameters change", async () => {
                    const address = this.governanceProtocolParams.vusdcAddress;
                    this.governanceProtocolParams.vusdcAddress =
                        ethers.constants.AddressZero;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.vusdcAddress = address;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).not.to.be.reverted;
                });
            });
            describe("USDC", () => {
                it("reverts when address zero, works as expected as a parameter", async () => {
                    await deployments.fixture();
                    const address = this.governanceProtocolParams.usdcAddress;
                    this.governanceProtocolParams.usdcAddress =
                        ethers.constants.AddressZero;
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton: this.perpVaultSingleton.address,
                                },
                                this.governanceProtocolParams,
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.usdcAddress = address;
                });
                it("works as expected in parameters change", async () => {
                    const address = this.governanceProtocolParams.usdcAddress;
                    this.governanceProtocolParams.usdcAddress =
                        ethers.constants.AddressZero;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.usdcAddress = address;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).not.to.be.reverted;
                });
            });
            describe("uniV3Factory", () => {
                it("reverts when address zero, works as expected as a parameter", async () => {
                    await deployments.fixture();
                    const address =
                        this.governanceProtocolParams.uniV3FactoryAddress;
                    this.governanceProtocolParams.uniV3FactoryAddress =
                        ethers.constants.AddressZero;
                    await expect(
                        deployments.deploy("PerpVaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                    singleton: this.perpVaultSingleton.address,
                                },
                                this.governanceProtocolParams,
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.uniV3FactoryAddress = address;
                });
                it("works as expected in parameters change", async () => {
                    const address =
                        this.governanceProtocolParams.uniV3FactoryAddress;
                    this.governanceProtocolParams.uniV3FactoryAddress =
                        ethers.constants.AddressZero;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    this.governanceProtocolParams.uniV3FactoryAddress = address;
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedProtocolParams(
                                this.governanceProtocolParams
                            )
                    ).not.to.be.reverted;
                });
            });

            describe("protocolLeverage", () => {
                it("okay any value", async () => {
                    await deployments.fixture();
                    const arr = [0, 1, 5, 10, 100, 10 ** 9];

                    const len = arr.length;

                    for (let i = 0; i < len; ++i) {
                        this.governanceProtocolParams.maxProtocolLeverage =
                            arr[i];

                        await expect(
                            deployments.deploy("PerpVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.perpVaultSingleton.address,
                                    },
                                    this.governanceProtocolParams,
                                ],
                                autoMine: true,
                            })
                        ).not.to.be.reverted;
                    }

                    this.governanceProtocolParams.maxProtocolLeverage = 10;
                });

                it("works as expected in parameters change", async () => {
                    const arr = [0, 1, 5, 10, 100, 10 ** 9];

                    const len = arr.length;
                    for (let i = 0; i < len; ++i) {
                        this.governanceProtocolParams.maxProtocolLeverage =
                            arr[i];
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageDelayedProtocolParams(
                                    this.governanceProtocolParams
                                )
                        ).not.to.be.reverted;
                    }

                    this.governanceProtocolParams.maxProtocolLeverage = 10;
                });
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${PERP_VAULT_GOVERNANCE_INTERFACE_ID} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        PERP_VAULT_GOVERNANCE_INTERFACE_ID
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

        const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> =
            tuple(
                address,
                address,
                address,
                address,
                address,
                address,
                integer({ min: 0, max: 10 ** 9 })
            ).map(
                ([
                    vault,
                    clearingHouse,
                    accountBalance,
                    vusdcAddress,
                    usdcAddress,
                    uniV3FactoryAddress,
                    x,
                ]) => ({
                    vault,
                    clearingHouse,
                    accountBalance,
                    vusdcAddress,
                    usdcAddress,
                    uniV3FactoryAddress,
                    maxProtocolLeverage: BigNumber.from(x),
                })
            );

        vaultGovernanceBehavior.call(this, {
            delayedProtocolParams,
            perpVaultGovernanceSpecial: true,
            ...this,
        });

        ContractMetaBehaviour.call(this, {
            contractName: "PerpVaultGovernance",
            contractVersion: "1.0.0",
        });
    }
);
