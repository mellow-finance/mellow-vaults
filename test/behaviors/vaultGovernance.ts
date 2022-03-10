import { BigNumber, Contract, Signer } from "ethers";
import { Arbitrary, Random } from "fast-check";
import { type } from "os";
import {
    randomAddress,
    sleep,
    toObject,
    withSigner,
    zeroify,
} from "../library/Helpers";
import { address, pit, RUNS } from "../library/property";
import { TestContext } from "../library/setup";
import { mersenne } from "pure-rand";
import { equals } from "ramda";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import Exceptions from "../library/Exceptions";
import { delayedProtocolParamsBehavior } from "./vaultGovernanceDelayedProtocolParams";
import { InternalParamsStruct } from "../types/IVaultGovernance";
import { ERC20Token as ERC20, IVault, Vault, VaultGovernance } from "../types";
import { InternalParamsStructOutput } from "../types/VaultGovernance";
import { deployments, ethers } from "hardhat";
import { delayedStrategyParamsBehavior } from "./vaultGovernanceDelayedStrategyParams";
import { create } from "domain";
import { PermissionIdsLibrary } from "../../deploy/0000_utils";
import { REGISTER_VAULT, CREATE_VAULT } from "../library/PermissionIdsLibrary";
import { delayedProtocolPerVaultParamsBehavior } from "./vaultGovernanceDelayedProtocolPerVaultParams";
import { operatorParamsBehavior } from "./vaultGovernanceOperatorParams";

export type VaultGovernanceContext<S extends Contract, F> = TestContext<
    S,
    F
> & {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

export function vaultGovernanceBehavior<
    DSP,
    SP,
    DPP,
    PP,
    DPPV,
    OP,
    S extends Contract
>(
    this: VaultGovernanceContext<
        S,
        {
            skipInit?: boolean;
            internalParams?: InternalParamsStruct;
        }
    >,
    {
        delayedStrategyParams,
        strategyParams,
        delayedProtocolParams,
        protocolParams,
        delayedProtocolPerVaultParams,
        operatorParams,
        defaultCreateVault,
        rootVaultGovernance,
    }: {
        delayedStrategyParams?: Arbitrary<DSP>;
        strategyParams?: Arbitrary<SP>;
        delayedProtocolParams?: Arbitrary<DPP>;
        protocolParams?: Arbitrary<PP>;
        delayedProtocolPerVaultParams?: Arbitrary<DPPV>;
        operatorParams?: Arbitrary<OP>;
        defaultCreateVault?: (
            deployer: Signer,
            tokenAddresses: string[],
            owner: string,
            ...args: any[]
        ) => Promise<void>;
        rootVaultGovernance?: boolean;
    }
) {
    describe("#constructor", () => {
        it("initializes internalParams", async () => {
            const params: InternalParamsStruct = {
                protocolGovernance: randomAddress(),
                registry: randomAddress(),
                singleton: randomAddress(),
            };
            await this.deploymentFixture({
                skipInit: true,
                internalParams: params,
            });
            expect(params).to.be.equivalent(
                await this.subject.internalParams()
            );
        });

        describe("edge cases", () => {
            describe("when protocolGovernance address is 0", () => {
                it("reverts", async () => {
                    const params: InternalParamsStruct = {
                        protocolGovernance: ethers.constants.AddressZero,
                        registry: randomAddress(),
                        singleton: randomAddress(),
                    };
                    await expect(
                        this.deploymentFixture({
                            skipInit: true,
                            internalParams: params,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                });
            });
            describe("when vaultRegistry address is 0", () => {
                it("reverts", async () => {
                    const params: InternalParamsStruct = {
                        protocolGovernance: randomAddress(),
                        registry: ethers.constants.AddressZero,
                        singleton: randomAddress(),
                    };
                    await expect(
                        this.deploymentFixture({
                            skipInit: true,
                            internalParams: params,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                });
            });
        });
    });

    describe("#createVault", () => {
        let createVaultFixture: Function;
        let lastNft: number;
        let nft: number;
        let subVaultNfts: BigNumber[];
        let createVault: (
            deployer: SignerWithAddress,
            tokenAddresses: string[],
            owner: string
        ) => Promise<void>;

        before(async () => {
            let isRootVaultGovernance = rootVaultGovernance ?? false;
            createVault = async (
                deployer: SignerWithAddress,
                tokenAddresses: string[],
                owner: string
            ) => {
                if (defaultCreateVault) {
                    await defaultCreateVault(deployer, tokenAddresses, owner);
                } else {
                    if (isRootVaultGovernance) {
                        subVaultNfts = await setSubVaultNfts(
                            deployer,
                            tokenAddresses
                        );
                        const { nft } = await this.subject
                            .connect(deployer)
                            .callStatic.createVault(
                                tokenAddresses,
                                this.strategySigner.address,
                                subVaultNfts,
                                this.ownerSigner.address
                            );

                        this.nft = nft;

                        await this.subject
                            .connect(deployer)
                            .createVault(
                                tokenAddresses,
                                this.strategySigner.address,
                                subVaultNfts,
                                this.ownerSigner.address
                            );
                    } else {
                        await this.subject
                            .connect(deployer)
                            .createVault(
                                tokenAddresses,
                                this.ownerSigner.address
                            );
                    }
                }
            };

            const setSubVaultNfts = async (
                ownerSigner: SignerWithAddress,
                tokens: string[]
            ) => {
                const { nft: nftERC20Vault } = await this.erc20VaultGovernance
                    .connect(ownerSigner)
                    .callStatic.createVault(tokens, ownerSigner.address);
                await this.erc20VaultGovernance
                    .connect(ownerSigner)
                    .createVault(tokens, ownerSigner.address);

                const { nft: nftYearnVault } = await this.yearnVaultGovernance
                    .connect(ownerSigner)
                    .callStatic.createVault(tokens, ownerSigner.address);
                await this.yearnVaultGovernance
                    .connect(ownerSigner)
                    .createVault(tokens, ownerSigner.address);

                let subVaultNfts = [nftERC20Vault, nftYearnVault];

                for (let i = 0; i < subVaultNfts.length; ++i) {
                    await this.vaultRegistry
                        .connect(ownerSigner)
                        .approve(this.subject.address, subVaultNfts[i]);
                }
                return subVaultNfts;
            };

            const setPermissionsRegisterAndCreateVault = async (
                ownerSigner: SignerWithAddress
            ) => {
                await this.protocolGovernance
                    .connect(this.admin)
                    .stagePermissionGrants(ownerSigner.address, [CREATE_VAULT]);
                await sleep(this.governanceDelay);
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitPermissionGrants(ownerSigner.address);

                await this.protocolGovernance
                    .connect(this.admin)
                    .stagePermissionGrants(ownerSigner.address, [
                        REGISTER_VAULT,
                    ]);
                await sleep(this.governanceDelay);
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitPermissionGrants(ownerSigner.address);

                await this.protocolGovernance
                    .connect(this.admin)
                    .stagePermissionGrants(this.subject.address, [
                        REGISTER_VAULT,
                    ]);
                await sleep(this.governanceDelay);
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitPermissionGrants(this.subject.address);
            };

            createVaultFixture = deployments.createFixture(async () => {
                await this.deploymentFixture();
                lastNft = (await this.vaultRegistry.vaultsCount()).toNumber();
                const tokenAddresses = this.tokens
                    .slice(0, 2)
                    .map((x: ERC20) => x.address);

                await setPermissionsRegisterAndCreateVault(this.ownerSigner);

                await createVault(
                    this.deployer,
                    tokenAddresses,
                    this.ownerSigner.address
                );
                nft = (await this.vaultRegistry.vaultsCount()).toNumber();
            });
        });
        beforeEach(async () => {
            await createVaultFixture();
        });
        it("deploys a new vault", async () => {
            const address = await this.vaultRegistry.vaultForNft(nft);
            const code = await ethers.provider.getCode(address);
            expect(code.length).to.be.gt(10);
        });

        it("registers vault with vault registry and issues nft", async () => {
            expect(nft).to.be.gt(lastNft);
        });

        it("the nft is owned by the owner from #createVault arguments", async () => {
            expect(this.ownerSigner.address).to.eq(
                await this.vaultRegistry.ownerOf(nft)
            );
        });
        it("vault is initialized with nft", async () => {
            const address = await this.vaultRegistry.vaultForNft(nft);
            const vault: IVault = await ethers.getContractAt("IVault", address);
            expect(nft).to.eq(await vault.nft());
        });
        it("vault sets ApprovedForAll for VaultRegistry", async () => {
            const address = await this.vaultRegistry.vaultForNft(nft);
            expect(true).to.eq(
                await this.vaultRegistry.isApprovedForAll(
                    address,
                    this.vaultRegistry.address
                )
            );
        });

        describe("access control", () => {
            describe("when permissionless", () => {
                it("allowed: any address", async () => {
                    const params = await this.protocolGovernance.params();
                    await this.protocolGovernance
                        .connect(this.admin)
                        .stageParams({
                            ...params,
                            forceAllowMask:
                                1 << PermissionIdsLibrary.CREATE_VAULT,
                        });
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitParams();

                    await withSigner(randomAddress(), async (s) => {
                        const tokenAddresses = this.tokens
                            .slice(0, 2)
                            .map((x: ERC20) => x.address);
                        if (defaultCreateVault) {
                            await defaultCreateVault(
                                s,
                                tokenAddresses,
                                this.ownerSigner.address
                            );
                        } else {
                            await createVault(
                                s,
                                tokenAddresses,
                                this.ownerSigner.address
                            );
                        }
                    });
                });
            });
            describe("when not permissionless", () => {
                beforeEach(async () => {
                    const params = await this.protocolGovernance.params();
                    await this.protocolGovernance
                        .connect(this.admin)
                        .stageParams({ ...params, forceAllowMask: 0 });
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitParams();
                });
                it("allowed: protocol governance admin", async () => {
                    const tokenAddresses = this.tokens
                        .slice(0, 2)
                        .map((x: ERC20) => x.address);
                    await createVault(
                        this.admin,
                        tokenAddresses,
                        this.ownerSigner.address
                    );
                });
                it("denied: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        const tokenAddresses = this.tokens.map(
                            (x: ERC20) => x.address
                        );
                        await expect(
                            createVault(
                                s,
                                tokenAddresses,
                                this.ownerSigner.address
                            )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });
    });

    if (delayedProtocolParams) {
        delayedProtocolParamsBehavior.call(this as any, delayedProtocolParams);
    }
    if (delayedStrategyParams) {
        delayedStrategyParamsBehavior.call(this as any, delayedStrategyParams);
    }
    if (delayedProtocolPerVaultParams) {
        delayedProtocolPerVaultParamsBehavior.call(
            this as any,
            delayedProtocolPerVaultParams
        );
    }
    if (operatorParams) {
        operatorParamsBehavior.call(this as any, operatorParams);
    }
}
