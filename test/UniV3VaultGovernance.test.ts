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
import { VAULT_GOVERNANCE } from "./library/PermissionIds";
import {
    DelayedProtocolParamsStruct,
    UniV3VaultGovernance,
} from "./types/UniV3VaultGovernance";
import { contract, setupDefaultContext, TestContext } from "./library/setup";
import { Context, Suite } from "mocha";
import { equals } from "ramda";
import { address, pit, RUNS } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, hexa, hexaString, nat, tuple } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import {
    InternalParamsStruct,
    InternalParamsStructOutput,
} from "./types/IVaultGovernance";
import { ERC20, IUniswapV3Pool, UniV3Vault } from "./types";
import { Signer } from "ethers";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};
type DeploymentOptions = {
    internalParams?: InternalParamsStruct;
    positionManager?: string;
    skipInit?: boolean;
};

contract<UniV3VaultGovernance, DeploymentOptions, CustomContext>(
    "UniV3VaultGovernance",
    function () {
        before(async () => {
            const positionManagerAddress = (await getNamedAccounts())
                .uniswapV3PositionManager;
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeploymentOptions) => {
                    await deployments.fixture();
                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton: this.uniV3VaultSingleton.address,
                        },
                        positionManager = positionManagerAddress,
                        skipInit = false,
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "UniV3VaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "UniV3VaultGovernance",
                            args: [
                                internalParams,
                                {
                                    positionManager,
                                    oracle: this.mellowOracle.address,
                                },
                            ],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "UniV3VaultGovernance",
                        address
                    );
                    this.ownerSigner = await addSigner(randomAddress());
                    this.strategySigner = await addSigner(randomAddress());

                    if (!skipInit) {
                        await this.protocolGovernance
                            .connect(this.admin)
                            .stageGrantPermissions(this.subject.address, [
                                VAULT_GOVERNANCE,
                            ]);
                        await sleep(this.governanceDelay);
                        await this.protocolGovernance
                            .connect(this.admin)
                            .commitStagedPermissions();
                        await this.subject.createVault(
                            this.tokens.slice(0, 2).map((x: any) => x.address),
                            this.ownerSigner.address,
                            3000
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
            tuple(address, address).map(([positionManager, oracle]) => ({
                positionManager,
                oracle,
            }));

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });

            describe("edge cases", () => {
                describe("when positionManager address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        await expect(
                            deployments.deploy("UniV3VaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.uniV3VaultSingleton.address,
                                    },
                                    {
                                        positionManager:
                                            ethers.constants.AddressZero,
                                        oracle: this.mellowOracle.address,
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
                describe("when oracle address is 0", () => {
                    it("reverts", async () => {
                        await deployments.fixture();
                        const positionManagerAddress = (
                            await getNamedAccounts()
                        ).uniswapV3PositionManager;
                        await expect(
                            deployments.deploy("UniV3VaultGovernance", {
                                from: this.deployer.address,
                                args: [
                                    {
                                        protocolGovernance:
                                            this.protocolGovernance.address,
                                        registry: this.vaultRegistry.address,
                                        singleton:
                                            this.uniV3VaultSingleton.address,
                                    },
                                    {
                                        positionManager: positionManagerAddress,
                                        oracle: ethers.constants.AddressZero,
                                    },
                                ],
                                autoMine: true,
                            })
                        ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                    });
                });
            });
        });

        describe("#createVault", () => {
            describe("edge cases", () => {
                describe("when fee is not supported by uni v3", () => {
                    it("reverts", async () => {
                        await expect(
                            this.subject.createVault(
                                [this.weth.address, this.usdc.address]
                                    .map((x) => x.toLowerCase())
                                    .sort(),
                                this.ownerSigner.address,
                                2345
                            )
                        ).to.be.revertedWith(Exceptions.NOT_FOUND);
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
                await this.subject
                    .connect(deployer)
                    .createVault(tokenAddresses, owner, 3000);
            },
            ...this,
        });
    }
);
