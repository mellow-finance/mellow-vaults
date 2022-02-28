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
    ERC20RootVaultGovernance,
} from "./types/ERC20RootVaultGovernance";
import { contract, setupDefaultContext, TestContext } from "./library/setup";
import { address, pit } from "./library/property";
import { Arbitrary } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStruct } from "./types/IERC20RootVaultGovernance";
import { IOracle } from "./types";
import { BigNumber, BigNumberish } from "ethers";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
    delayedProtocolParams: DelayedProtocolParamsStruct;
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
                        managementFeeChargeDelay: BigNumber.from(86400), // use randomInt
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

        describe("#delayedProtocolParams", () => {
            it("successfully get delayedProtocolParams", async () => {
                expect(
                    toObject(await this.subject.delayedProtocolParams())
                ).to.be.equivalent(this.delayedProtocolParams);
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
                const nft = BigNumber.from(4);
                // this.object._delayedProtocolPerVaultParamsTimestamp[nft.toNumber()] =
                //     nft.toNumber()
                // fix exceptions:
                //     _delayedProtocolPerVaultParamsTimestamp[nft] != 0, ExceptionsLibrary.NULL
                //     block.timestamp >= _delayedProtocolPerVaultParamsTimestamp[nft], ExceptionsLibrary.TIMESTAMP
                const expected: DelayedProtocolPerVaultParamsStruct = {
                    protocolFee: BigNumber.from(3),
                };
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolPerVaultParams(nft);

                // expect(
                //     toObject(await this.subject
                //     .delayedProtocolPerVaultParams(nft))
                // ).to.be.equivalent(expected);
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
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .delayedProtocolPerVaultParams(
                                    BigNumber.from(2)
                                )
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#stagedDelayedProtocolPerVaultParams", () => {
            it("returns stagedDelayedProtocolPerVaultParams", async () => {
                const nft = BigNumber.from(5);
                const expected: DelayedProtocolPerVaultParamsStruct = {
                    protocolFee: BigNumber.from(3),
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
                        const expected: DelayedProtocolPerVaultParamsStruct = {
                            protocolFee: BigNumber.from(0),
                        };
                        expect(
                            toObject(
                                await this.subject.stagedDelayedProtocolPerVaultParams(
                                    BigNumber.from(1)
                                )
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
                                .stagedDelayedProtocolPerVaultParams(
                                    BigNumber.from(2)
                                )
                        ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        // describe("#stageDelayedProtocolParams", () => {
        //     describe("access control", () => {
        //         it(`reverted with ${Exceptions.FORBIDDEN}`, () => {
        //             expect(await this.subject.stageDelayedProtocolParams(expected))
        //             .to.be.;
        //         });
        //     });
        // });

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

        // vaultGovernanceBehavior.call(this, {
        //     delayedProtocolParams,
        //     ...this,
        // });
    }
);
