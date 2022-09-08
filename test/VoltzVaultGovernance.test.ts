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
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import {
    DelayedProtocolParamsStruct,
    VoltzVaultGovernance,
} from "./types/VoltzVaultGovernance";
import { contract } from "./library/setup";
import { Arbitrary, integer } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import {
    InternalParamsStruct,
} from "./types/IVaultGovernance";
import { BigNumber, Signer } from "ethers";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";
import { randomBytes } from "crypto";
import { VOLTZ_VAULT_GOVERNANCE_INTERFACE_ID } from "./library/Constants";
import { address } from "./library/property";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};
type DeploymentOptions = {
    internalParams?: InternalParamsStruct;
    marginEngine?: string;
    skipInit?: boolean;
};

contract<VoltzVaultGovernance, DeploymentOptions, CustomContext>(
    "VoltzVaultGovernance",
    function () {
        before(async () => {
            const marginEngineAddress = (await getNamedAccounts())
                .marginEngine;
            
            const voltzPeripheryAddress = (await getNamedAccounts())
                .voltzPeriphery;   
            
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeploymentOptions) => {
                    await deployments.fixture();
                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton: this.voltzVaultSingleton.address,
                        },
                        marginEngine = marginEngineAddress,
                        skipInit = false,
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "VoltzVaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "VoltzVaultGovernance",
                            args: [
                                internalParams,
                                {
                                    periphery: voltzPeripheryAddress,
                                }],
                            autoMine: true,
                        }
                    );
                    
                    this.subject = await ethers.getContractAt(
                        "VoltzVaultGovernance",
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
                        this.marginEngine = marginEngineAddress;

                        await this.subject.createVault(
                            ["0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"], // USDC
                            this.ownerSigner.address,
                            marginEngine,
                            0, 
                            60
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
            address.map((periphery) => ({
                periphery
            }));

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${VOLTZ_VAULT_GOVERNANCE_INTERFACE_ID} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        VOLTZ_VAULT_GOVERNANCE_INTERFACE_ID
                    )
                ).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
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
                _,
                owner: string
            ) => {
                await this.subject
                    .connect(deployer)
                    .createVault(["0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"], owner, this.marginEngine, 0, 60);
            },
            ...this,
        });

        ContractMetaBehaviour.call(this, {
            contractName: "VoltzVaultGovernance",
            contractVersion: "1.0.0",
        });
    }
);
