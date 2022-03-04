import { expect } from "chai";
import hre, { ethers, deployments, getNamedAccounts } from "hardhat";
import { setupVault, combineVaults } from "../deploy/0000_utils";
import { YearnVault } from "./types/YearnVault";
import { ERC20Vault } from "./types/ERC20Vault";
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
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import {
    DelayedProtocolParamsStruct,
    DelayedProtocolPerVaultParamsStruct,
    DelayedStrategyParamsStruct,
    ERC20RootVaultGovernance,
} from "./types/ERC20RootVaultGovernance";
import { contract, setupDefaultContext, TestContext } from "./library/setup";
import { address, pit } from "./library/property";
import { Arbitrary, integer } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import {
    InternalParamsStruct,
    OperatorParamsStruct,
    StrategyParamsStruct,
} from "./types/IERC20RootVaultGovernance";
import { IOracle } from "./types";
import { BigNumber, BigNumberish } from "ethers";
import { randomInt } from "crypto";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
    delayedProtocolParams: DelayedProtocolParamsStruct;
    MAX_MANAGEMENT_FEE: BigNumber;
    MAX_PERFORMANCE_FEE: BigNumber;
};

type DeployOptions = {
    internalParams?: InternalParamsStruct;
    delayedProtocolParams?: DelayedProtocolParamsStruct;
};

contract<ERC20RootVaultGovernance, DeployOptions, CustomContext>(
    "ERC20RootVaultGovernance",
    function () {
        before(async () => {
            const mellowOracle = await ethers.getContract("MellowOracle");
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();
                    this.delayedProtocolParams = {
                        managementFeeChargeDelay: BigNumber.from(86400), // BigNumber.from(randomInt(10 ** 6))
                        oracle: mellowOracle.address,
                    };
                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton: ethers.constants.AddressZero,
                        },
                        delayedProtocolParams = this.delayedProtocolParams,
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "ERC20RootVaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "ERC20RootVaultGovernance",
                            args: [internalParams, delayedProtocolParams],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "ERC20RootVaultGovernance",
                        address
                    );
                    this.ownerSigner = await addSigner(randomAddress());
                    this.strategySigner = await addSigner(randomAddress());

                    await this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(this.subject.address, [
                            REGISTER_VAULT,
                        ]);
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitPermissionGrants(this.subject.address);

                    // const { read } = deployments;
                    // const tokens = [this.weth.address, this.usdc.address]
                    //     .map((t) => t.toLowerCase())
                    //     .sort();
                    // const startNft =
                    //     (
                    //         await read("VaultRegistry", "vaultsCount")
                    //     ).toNumber() + 1;

                    // const startNft = (await this.vaultRegistry.vaultsCount()).toNumber() + 1;
                    // console.log("Start NFT: ", startNft);
                    // let erc20VaultNft = startNft;
                    // let yearnVaultNft = startNft + 1;
                    // await setupVault(
                    //     hre,
                    //     erc20VaultNft,
                    //     "ERC20VaultGovernance",
                    //     {
                    //         createVaultArgs: [tokens, this.deployer.address],
                    //     }
                    // );
                    // console.log("after setupERC20Vault");
                    // await setupVault(
                    //     hre,
                    //     yearnVaultNft,
                    //     "YearnVaultGovernance",
                    //     {
                    //         createVaultArgs: [tokens, this.deployer.address],
                    //     }
                    // );
                    // console.log("after setupYearnVault");

                    // const erc20Vault = await read(
                    //     "VaultRegistry",
                    //     "vaultForNft",
                    //     erc20VaultNft
                    // );
                    // const yearnVault = await read(
                    //     "VaultRegistry",
                    //     "vaultForNft",
                    //     yearnVaultNft
                    // );

                    // const erc20RootVault = await read(
                    //     "VaultRegistry",
                    //     "vaultForNft",
                    //     yearnVaultNft + 1
                    // );

                    // this.erc20Vault = (await ethers.getContractAt(
                    //     "ERC20Vault",
                    //     erc20Vault
                    // )) as ERC20Vault;
                    // this.yearnVault = (await ethers.getContractAt(
                    //     "YearnVault",
                    //     yearnVault
                    // )) as YearnVault;

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
        });

        // describe("#supportsInterface", () => {
        //     it(`returns true if this contract supports ${ERC20ROOT_VAULT_INTERFACE_ID} interface`, async () => {
        //         expect(
        //             await this.subject.supportsInterface(AAVE_VAULT_INTERFACE_ID)
        //         ).to.be.true;
        //     });

        //     describe("access control:", () => {
        //         it("allowed: any address", async () => {
        //             await withSigner(randomAddress(), async (s) => {
        //                 await expect(
        //                     this.subject
        //                         .connect(s)
        //                         .supportsInterface(INTEGRATION_VAULT_INTERFACE_ID)
        //                 ).to.not.be.reverted;
        //             });
        //         });
        //     });
        // });

        describe("#delayedProtocolParams", () => {
            it("successfully get delayedProtocolParams", async () => {
                expect(
                    toObject(await this.subject.delayedProtocolParams())
                ).to.be.equivalent(this.delayedProtocolParams);
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).delayedProtocolParams()
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#stagedDelayedProtocolParams", () => {
            it("returns stagedDelayedProtocolParams", async () => {
                const expected = this.delayedProtocolParams;
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(expected);
                expect(
                    toObject(await this.subject.stagedDelayedProtocolParams())
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("length of stagedDelayedProtocolParams equals to zero", () => {
                    it("returns object with zero values", async () => {
                        const expected: DelayedProtocolParamsStruct = {
                            managementFeeChargeDelay: BigNumber.from(0),
                            oracle: ethers.constants.AddressZero,
                        };
                        expect(
                            toObject(
                                await this.subject.stagedDelayedProtocolParams()
                            )
                        ).to.be.equivalent(expected);
                    });
                });
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagedDelayedProtocolParams()
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#delayedProtocolPerVaultParams", () => {
            it("returns delayedProtocolPerVaultParams", async () => {
                const nft = BigNumber.from(randomInt(100));
                const expected: DelayedProtocolPerVaultParamsStruct = {
                    protocolFee: BigNumber.from(randomInt(10 ** 6)),
                };
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolPerVaultParams(nft, expected);
                await sleep(this.governanceDelay);
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolPerVaultParams(nft);

                expect(
                    toObject(
                        await this.subject.delayedProtocolPerVaultParams(nft)
                    )
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("length of delayedProtocolPerVaultParams equals to zero", () => {
                    it("returns object with zero protocol fee", async () => {
                        const expected: DelayedProtocolPerVaultParamsStruct = {
                            protocolFee: BigNumber.from(0),
                        };
                        expect(
                            toObject(
                                await this.subject.delayedProtocolPerVaultParams(
                                    BigNumber.from(1)
                                )
                            )
                        ).to.be.equivalent(expected);
                    });
                });
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    const nft = BigNumber.from(randomInt(100));
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .delayedProtocolPerVaultParams(nft)
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#stagedDelayedProtocolPerVaultParams", () => {
            it("returns stagedDelayedProtocolPerVaultParams", async () => {
                const nft = BigNumber.from(randomInt(100));
                const expected: DelayedProtocolPerVaultParamsStruct = {
                    protocolFee: BigNumber.from(randomInt(10 ** 6)),
                };
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolPerVaultParams(nft, expected);
                expect(
                    toObject(
                        await this.subject.stagedDelayedProtocolPerVaultParams(
                            nft
                        )
                    )
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("length of stagedDelayedProtocolPerVaultParams equals to zero", () => {
                    it("returns object with zero protocol fee", async () => {
                        const nft = BigNumber.from(randomInt(100));
                        const expected: DelayedProtocolPerVaultParamsStruct = {
                            protocolFee: BigNumber.from(0),
                        };
                        expect(
                            toObject(
                                await this.subject.stagedDelayedProtocolPerVaultParams(
                                    nft
                                )
                            )
                        ).to.be.equivalent(expected);
                    });
                });
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    const nft = BigNumber.from(randomInt(100));
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagedDelayedProtocolPerVaultParams(nft)
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#stagedDelayedStrategyParams", () => {
            it("returns stagedDelayedStrategyParams", async () => {
                const nft = BigNumber.from(randomInt(100));
                const expected: DelayedStrategyParamsStruct = {
                    strategyTreasury: randomAddress(),
                    strategyPerformanceTreasury: randomAddress(),
                    privateVault: false,
                    managementFee: BigNumber.from(randomInt(10 ** 6)),
                    performanceFee: BigNumber.from(randomInt(10 ** 6)),
                };

                await this.subject
                    .connect(this.admin)
                    .stageDelayedStrategyParams(nft, expected);
                expect(
                    toObject(
                        await this.subject.stagedDelayedStrategyParams(nft)
                    )
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("length of stagedDelayedStrategyParams equals to zero", () => {
                    it("returns zero object", async () => {
                        const nft = BigNumber.from(randomInt(100));
                        const expected: DelayedStrategyParamsStruct = {
                            strategyTreasury: ethers.constants.AddressZero,
                            strategyPerformanceTreasury:
                                ethers.constants.AddressZero,
                            privateVault: false,
                            managementFee: BigNumber.from(0),
                            performanceFee: BigNumber.from(0),
                        };
                        expect(
                            toObject(
                                await this.subject.stagedDelayedStrategyParams(
                                    nft
                                )
                            )
                        ).to.be.equivalent(expected);
                    });
                });
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    const nft = BigNumber.from(randomInt(100));
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .stagedDelayedStrategyParams(nft)
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#operatorParams", () => {
            it("returns operatorParams", async () => {
                const expected: OperatorParamsStruct = {
                    disableDeposit: false,
                };
                await this.subject
                    .connect(this.admin)
                    .setOperatorParams(expected);
                expect(
                    toObject(await this.subject.operatorParams())
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("length of operatorParams equals to zero", () => {
                    it("returns zero object", async () => {
                        const expected: OperatorParamsStruct = {
                            disableDeposit: false,
                        };
                        expect(
                            toObject(await this.subject.operatorParams())
                        ).to.be.equivalent(expected);
                    });
                });
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).operatorParams()
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#delayedStrategyParams", () => {
            it("returns delayedStrategyParams", async () => {
                const nft = BigNumber.from(randomInt(100));
                const expected: DelayedStrategyParamsStruct = {
                    strategyTreasury: randomAddress(),
                    strategyPerformanceTreasury: randomAddress(),
                    privateVault: false,
                    managementFee: BigNumber.from(randomInt(10 ** 6)),
                    performanceFee: BigNumber.from(randomInt(10 ** 6)),
                };
                await this.subject
                    .connect(this.admin)
                    .stageDelayedStrategyParams(nft, expected);
                await sleep(this.governanceDelay);
                await this.subject
                    .connect(this.admin)
                    .commitDelayedStrategyParams(nft);

                expect(
                    toObject(await this.subject.delayedStrategyParams(nft))
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("length of delayedStrategyParams equals to zero", () => {
                    it("returns zero object", async () => {
                        const nft = BigNumber.from(randomInt(100));
                        const expected: DelayedStrategyParamsStruct = {
                            strategyTreasury: ethers.constants.AddressZero,
                            strategyPerformanceTreasury:
                                ethers.constants.AddressZero,
                            privateVault: false,
                            managementFee: BigNumber.from(0),
                            performanceFee: BigNumber.from(0),
                        };
                        expect(
                            toObject(
                                await this.subject.delayedStrategyParams(nft)
                            )
                        ).to.be.equivalent(expected);
                    });
                });
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    const nft = BigNumber.from(randomInt(100));
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .delayedStrategyParams(nft)
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#strategyParams", () => {
            it("returns strategyParams", async () => {
                const nft = BigNumber.from(randomInt(100));
                const expected: StrategyParamsStruct = {
                    tokenLimitPerAddress: BigNumber.from(randomInt(10 ** 6)),
                    tokenLimit: BigNumber.from(randomInt(10 ** 6)),
                };
                await this.subject
                    .connect(this.admin)
                    .setStrategyParams(nft, expected);
                expect(
                    toObject(await this.subject.strategyParams(nft))
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("length of delayedStrategyParams equals to zero", () => {
                    it("returns zero object", async () => {
                        const nft = BigNumber.from(randomInt(100));
                        const expected: StrategyParamsStruct = {
                            tokenLimitPerAddress: BigNumber.from(0),
                            tokenLimit: BigNumber.from(0),
                        };
                        expect(
                            toObject(await this.subject.strategyParams(nft))
                        ).to.be.equivalent(expected);
                    });
                });
            });

            describe("access control", () => {
                it("allow any address", async () => {
                    const nft = BigNumber.from(randomInt(100));
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject.connect(signer).strategyParams(nft)
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        // setters

        describe("#stageDelayedStrategyParams", () => {
            it("stages delayedStrategyParams", async () => {
                const nft = BigNumber.from(randomInt(100));
                const expected: DelayedStrategyParamsStruct = {
                    strategyTreasury: randomAddress(),
                    strategyPerformanceTreasury: randomAddress(),
                    privateVault: false,
                    managementFee: BigNumber.from(randomInt(10 ** 6)), // 10 * 10**9 / 100 this.object.MAX_MANAGEMENT_FEE)),
                    performanceFee: BigNumber.from(randomInt(10 ** 6)), // 50 * 10**9 / 100 this.object.MAX_PERFORMANCE_FEE)),
                };
                await this.subject
                    .connect(this.admin)
                    .stageDelayedStrategyParams(nft, expected);
                expect(
                    toObject(
                        await this.subject.stagedDelayedStrategyParams(nft)
                    )
                ).to.be.equivalent(expected);
            });

            describe("edge cases", () => {
                describe("managementFee exceeds MAX_MANAGEMENT_FEE", () => {
                    it(`reverted with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                        const nft = BigNumber.from(randomInt(100));
                        const params: DelayedStrategyParamsStruct = {
                            strategyTreasury: randomAddress(),
                            strategyPerformanceTreasury: randomAddress(),
                            privateVault: false,
                            managementFee: BigNumber.from(10 * 10 ** 9 + 1), // 10 * 10**9 / 100 this.object.MAX_MANAGEMENT_FEE)),
                            performanceFee: BigNumber.from(randomInt(10 ** 6)), // 50 * 10**9 / 100 this.object.MAX_PERFORMANCE_FEE)),
                        };

                        await expect(
                            this.subject.stageDelayedStrategyParams(nft, params)
                        ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                    });
                });

                describe("performanceFee exceeds MAX_PERFORMANCE_FEE", () => {
                    it(`reverted with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                        const nft = BigNumber.from(randomInt(100));
                        const params: DelayedStrategyParamsStruct = {
                            strategyTreasury: randomAddress(),
                            strategyPerformanceTreasury: randomAddress(),
                            privateVault: false,
                            managementFee: BigNumber.from(randomInt(10 ** 6)), // 10 * 10**9 / 100 this.object.MAX_MANAGEMENT_FEE)),
                            performanceFee: BigNumber.from(50 * 10 ** 9 + 1), // 50 * 10**9 / 100 this.object.MAX_PERFORMANCE_FEE)),
                        };

                        await expect(
                            this.subject.stageDelayedStrategyParams(nft, params)
                        ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                    });
                });
            });

            describe("access control", () => {
                it("allow only protocol admin", async () => {
                    const nft = BigNumber.from(randomInt(100));
                    const params: DelayedStrategyParamsStruct = {
                        strategyTreasury: randomAddress(),
                        strategyPerformanceTreasury: randomAddress(),
                        privateVault: false,
                        managementFee: BigNumber.from(randomInt(10 ** 6)), // 10 * 10**9 / 100 this.object.MAX_MANAGEMENT_FEE)),
                        performanceFee: BigNumber.from(randomInt(10 ** 6)), // 50 * 10**9 / 100 this.object.MAX_PERFORMANCE_FEE)),
                    };
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .stageDelayedStrategyParams(nft, params)
                    ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                });

                it(`reverted with ${Exceptions.FORBIDDEN}`, async () => {
                    const nft = BigNumber.from(randomInt(100));
                    const params: DelayedStrategyParamsStruct = {
                        strategyTreasury: randomAddress(),
                        strategyPerformanceTreasury: randomAddress(),
                        privateVault: false,
                        managementFee: BigNumber.from(randomInt(10 ** 6)), // 10 * 10**9 / 100 this.object.MAX_MANAGEMENT_FEE)),
                        performanceFee: BigNumber.from(randomInt(10 ** 6)), // 50 * 10**9 / 100 this.object.MAX_PERFORMANCE_FEE)),
                    };
                    await expect(
                        this.subject.stageDelayedStrategyParams(nft, params)
                    ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });

        // other tests insert here

        describe("#setStrategyParams", () => {
            it("sets strategyParams", async () => {
                const nft = BigNumber.from(randomInt(100));
                const expected: StrategyParamsStruct = {
                    tokenLimitPerAddress: BigNumber.from(randomInt(10 ** 6)),
                    tokenLimit: BigNumber.from(randomInt(10 ** 6)),
                };
                await this.subject
                    .connect(this.admin)
                    .setStrategyParams(nft, expected);
                expect(
                    toObject(await this.subject.strategyParams(nft))
                ).to.be.equivalent(expected);
            });

            describe("access control", () => {
                it(`reverted with ${Exceptions.FORBIDDEN}`, async () => {
                    const nft = BigNumber.from(randomInt(100));
                    const params: StrategyParamsStruct = {
                        tokenLimitPerAddress: BigNumber.from(
                            randomInt(10 ** 6)
                        ),
                        tokenLimit: BigNumber.from(randomInt(10 ** 6)),
                    };
                    await expect(
                        this.subject.setStrategyParams(nft, params)
                    ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });

        describe("#setOperatorParams", () => {
            it("stages delayedProtocloParams", async () => {
                const expected: OperatorParamsStruct = {
                    disableDeposit: false,
                };
                await this.subject
                    .connect(this.admin)
                    .setOperatorParams(expected);
                expect(
                    toObject(await this.subject.operatorParams())
                ).to.be.equivalent(expected);
            });

            describe("access control", () => {
                it(`reverted with ${Exceptions.FORBIDDEN}`, async () => {
                    const params: OperatorParamsStruct = {
                        disableDeposit: false,
                    };
                    await expect(
                        this.subject.setOperatorParams(params)
                    ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });

        describe("#stageDelayedProtocolParams", () => {
            it("stages delayedProtocloParams", async () => {
                const expected: DelayedProtocolParamsStruct = {
                    managementFeeChargeDelay: BigNumber.from(
                        randomInt(10 ** 6)
                    ),
                    oracle: randomAddress(),
                };
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(expected);
                expect(
                    toObject(await this.subject.stagedDelayedProtocolParams())
                ).to.be.equivalent(expected);
            });

            describe("access control", () => {
                describe("allow only protocol admin", () => {
                    it("passes", async () => {
                        const params: DelayedProtocolParamsStruct = {
                            managementFeeChargeDelay: BigNumber.from(
                                randomInt(10 ** 6)
                            ),
                            oracle: randomAddress(),
                        };
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .stageDelayedProtocolParams(params)
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                describe("any user denied: any non admin address", () => {
                    it(`reverted with ${Exceptions.FORBIDDEN}`, async () => {
                        const params: DelayedProtocolParamsStruct = {
                            managementFeeChargeDelay: BigNumber.from(
                                randomInt(10 ** 6)
                            ),
                            oracle: randomAddress(),
                        };
                        await expect(
                            this.subject.stageDelayedProtocolParams(params)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        //     it("successfully deployed", async () => {
        //         await deployments.fixture();
        //         const { address: singleton } = await deployments.get(
        //             "ERC20RootVault"
        //         );
        //         await deployments.deploy("ERC20RootVaultGovernance", {
        //             from: this.deployer.address,
        //             args: [
        //                 {
        //                     protocolGovernance:
        //                         this.protocolGovernance.address,
        //                     registry: this.vaultRegistry.address,
        //                     singleton,
        //                 },
        //                 {
        //                     erc20RootVaultRegistry:
        //                         ethers.constants.AddressZero,
        //                 },
        //             ],
        //             autoMine: true,
        //         });
        //     });

        // describe("#stageDelayedStrategyParams", () => {
        //     describe("when protocol fee is more than MAX_PROTOCOL_FEE", () => {
        //         it("reverts", async () => {
        //             const delayedProtocolPerVaultsParams = await this.subject.delayedProtocolPerVaultParams(
        //                 1
        //             )

        //             const delayedProtocolPerVaultsParams1 = this.object.DelayedProtocolPerVaultParams({protocolFee: 0})

        //             await expect(this.subject.stageDelayedProtocolPerVaultParams(
        //                 1,
        //                 delayedProtocolPerVaultsParams)
        //             ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);

        //             await deployments.fixture();
        //             const { address: singleton } = await deployments.get(
        //                 "YearnVault"
        //             );
        //             await expect(
        //                 deployments.deploy("YearnVaultGovernance", {
        //                     from: this.deployer.address,
        //                     args: [
        //                         {
        //                             protocolGovernance:
        //                                 this.protocolGovernance.address,
        //                             registry: this.vaultRegistry.address,
        //                             singleton,
        //                         },
        //                         {
        //                             yearnVaultRegistry:
        //                                 ethers.constants.AddressZero,
        //                         },
        //                     ],
        //                     autoMine: true,
        //                 })
        //             ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
        //         });
        //     });
        // });

        // const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> = {
        //     managementFeeChargeDelay: randomInt(100),
        //     oracle: randomAddress()
        // };

        // // const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> = {
        // //     address.map((yearnVaultRegistry) => ({
        // //         yearnVaultRegistry,
        // //     })),
        // //     integer({ min: , max: } )
        // // };

        // vaultGovernanceBehavior.call(this, {
        //     this.delayedProtocolParams,
        //     ...this,
        // });
    }
);
