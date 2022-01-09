import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import {
    DelayedProtocolParamsStruct,
    YearnVaultGovernance,
} from "./types/YearnVaultGovernance";
import { contract, setupDefaultContext, TestContext } from "./library/setup";
import { address, pit } from "./library/property";
import { Arbitrary } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStruct } from "./types/IYearnVaultGovernance";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};
type DeployOptions = {
    internalParams?: InternalParamsStruct;
    yearnVaultRegistry?: string;
    skipInit?: boolean;
};

contract<YearnVaultGovernance, DeployOptions, CustomContext>(
    "YearnVaultGovernance",
    function () {
        before(async () => {
            const yearnVaultRegistryAddress = (await getNamedAccounts())
                .yearnVaultRegistry;
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();
                    const { address: singleton } = await deployments.get(
                        "YearnVault"
                    );
                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton,
                        },
                        yearnVaultRegistry = yearnVaultRegistryAddress,
                        skipInit = false,
                    } = options || {};

                    const { address } = await deployments.deploy(
                        "YearnVaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "YearnVaultGovernance",
                            args: [internalParams, { yearnVaultRegistry }],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "YearnVaultGovernance",
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
                        await this.subject.createVault(
                            this.tokens.map((x: any) => x.address),
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
            address.map((yearnVaultRegistry) => ({ yearnVaultRegistry }));

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });

            describe("edge cases", () => {
                describe("when YearnVaultRegistry address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        const { address: singleton } = await deployments.get(
                            "YearnVault"
                        );
                        await expect(
                            deployments.deploy("YearnVaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton,
                                    },
                                    {
                                        yearnVaultRegistry:
                                            ethers.constants.AddressZero,
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#yTokenForToken", () => {
            let yearnWethPool: string;

            before(async () => {
                ({ yearnWethPool } = await getNamedAccounts());
            });

            it(`returns yToken (yVault) in yToken overrides (set by #setYTokenForToken) 
            or corresponding to ERC20 token in YearnVaultRegistry`, async () => {
                const yToken = await this.subject.yTokenForToken(
                    this.weth.address
                );
                expect(yearnWethPool).to.eq(yToken);
            });

            describe("access control", () => {
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
                        expect(yearnWethPool).to.eq(yToken);
                    });
                });

                describe("when yToken was overridden by #setYTokenForToken", () => {
                    it("returns overridden token", async () => {
                        const yTokenAddress = randomAddress();
                        await this.subject
                            .connect(this.admin)
                            .setYTokenForToken(
                                this.weth.address,
                                yTokenAddress
                            );
                        expect(yTokenAddress).to.eq(
                            await this.subject.yTokenForToken(this.weth.address)
                        );
                    });
                });
            });
        });

        describe("#setYTokenForToken", () => {
            let yTokenAddress: string;
            beforeEach(async () => {
                yTokenAddress = randomAddress();
            });
            it("sets a yToken override for a ERC20 token", async () => {
                await this.subject
                    .connect(this.admin)
                    .setYTokenForToken(this.weth.address, yTokenAddress);
                expect(yTokenAddress).to.eq(
                    await this.subject.yTokenForToken(this.weth.address)
                );
            });

            it("emits SetYToken event", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .setYTokenForToken(this.weth.address, yTokenAddress)
                ).to.emit(this.subject, "SetYToken");
            });

            describe("access control", () => {
                it("allowed: ProtocolGovernance admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .setYTokenForToken(this.weth.address, yTokenAddress)
                    ).to.not.be.reverted;
                });

                it("denied: Vault NFT Owner (aka liquidity provider)", async () => {
                    await expect(
                        this.subject
                            .connect(this.ownerSigner)
                            .setYTokenForToken(this.weth.address, yTokenAddress)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: Vault NFT Approved (aka strategy)", async () => {
                    await expect(
                        this.subject
                            .connect(this.strategySigner)
                            .setYTokenForToken(this.weth.address, yTokenAddress)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
                it("denied: deployer", async () => {
                    await expect(
                        this.subject
                            .connect(this.deployer)
                            .setYTokenForToken(this.weth.address, yTokenAddress)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });

                it("denied: random address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .setYTokenForToken(
                                    this.weth.address,
                                    yTokenAddress
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            describe("edge cases", () => {
                describe("when yToken is 0", () => {
                    it("succeeds", async () => {
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .setYTokenForToken(
                                    this.weth.address,
                                    ethers.constants.AddressZero
                                )
                        ).to.not.be.reverted;
                    });
                });

                describe("when called twice", () => {
                    it("succeeds", async () => {
                        await this.subject
                            .connect(this.admin)
                            .setYTokenForToken(
                                this.weth.address,
                                yTokenAddress
                            );
                        const otherAddress = randomAddress();
                        await this.subject
                            .connect(this.admin)
                            .setYTokenForToken(this.weth.address, otherAddress);

                        expect(otherAddress).to.eq(
                            await this.subject.yTokenForToken(this.weth.address)
                        );
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
