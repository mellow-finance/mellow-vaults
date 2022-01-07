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
import { ERC20, IVault, Vault, VaultGovernance } from "../types";
import { InternalParamsStructOutput } from "../types/VaultGovernance";
import { deployments, ethers } from "hardhat";
import { delayedStrategyParamsBehavior } from "./vaultGovernanceDelayedStrategyParams";
import { create } from "domain";

const random = new Random(mersenne(Math.floor(Math.random() * 100000)));

export function generateParams<T extends Object>(
    params: Arbitrary<T>
): { someParams: T; noneParams: T } {
    const someParams: T = params
        .filter((x: T) => !equals(x, zeroify(x)))
        .generate(random).value;
    const noneParams: T = zeroify(someParams);
    return { someParams, noneParams };
}

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
        defaultCreateVault,
    }: {
        delayedStrategyParams?: Arbitrary<DSP>;
        strategyParams?: Arbitrary<SP>;
        delayedProtocolParams?: Arbitrary<DPP>;
        protocolParams?: Arbitrary<PP>;
        delayedProtocolPerVaultParams?: Arbitrary<DPPV>;
        defaultCreateVault?: (
            deployer: Signer,
            tokenAddresses: string[],
            owner: string,
            ...args: any[]
        ) => Promise<void>;
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
        let createVault: (
            deployer: Signer,
            tokenAddresses: string[],
            owner: string
        ) => Promise<void>;
        before(async () => {
            createVault = async (
                deployer: Signer,
                tokenAddresses: string[],
                owner: string
            ) => {
                if (defaultCreateVault) {
                    await defaultCreateVault(deployer, tokenAddresses, owner);
                } else {
                    await this.subject
                        .connect(deployer)
                        .createVault(tokenAddresses, this.ownerSigner.address);
                }
            };
            createVaultFixture = deployments.createFixture(async () => {
                await this.deploymentFixture();
                lastNft = (await this.vaultRegistry.vaultsCount()).toNumber();
                const tokenAddresses = this.tokens
                    .slice(0, 2)
                    .map((x: ERC20) => x.address);
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
        it("vault sets AprrovedForAll for VaultRegistry", async () => {
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
                        .setPendingParams({
                            ...params,
                            forceAllowMask: 2 ** 5,
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
                            await this.subject
                                .connect(s)
                                .createVault(
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
                        .setPendingParams({ ...params, forceAllowMask: 0 });
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
}
