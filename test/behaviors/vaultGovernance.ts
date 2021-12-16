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
    }: {
        delayedStrategyParams?: Arbitrary<DSP>;
        strategyParams?: Arbitrary<SP>;
        delayedProtocolParams?: Arbitrary<DPP>;
        protocolParams?: Arbitrary<PP>;
        delayedProtocolPerVaultParams?: Arbitrary<DPPV>;
    }
) {
    describe("#constructor", () => {
        it("initializes internalParams", async () => {
            const params: InternalParamsStruct = {
                protocolGovernance: randomAddress(),
                registry: randomAddress(),
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
                    };
                    await expect(
                        this.deploymentFixture({
                            skipInit: true,
                            internalParams: params,
                        })
                    ).to.be.revertedWith(
                        Exceptions.PROTOCOL_GOVERNANCE_ADDRESS_ZERO
                    );
                });
            });
            describe("when vaultRegistry address is 0", () => {
                it("reverts", async () => {
                    const params: InternalParamsStruct = {
                        protocolGovernance: randomAddress(),
                        registry: ethers.constants.AddressZero,
                    };
                    await expect(
                        this.deploymentFixture({
                            skipInit: true,
                            internalParams: params,
                        })
                    ).to.be.revertedWith(
                        Exceptions.VAULT_REGISTRY_ADDRESS_ZERO
                    );
                });
            });
        });
    });
    describe("#factory", () => {
        it("is 0 after contract creation", async () => {
            await this.deploymentFixture({ skipInit: true });
            expect(ethers.constants.AddressZero).to.eq(
                await this.subject.factory()
            );
        });
        it("is initialized with address after #initialize is called", async () => {
            const factoryAddress = randomAddress();
            await this.deploymentFixture({ skipInit: true });
            await this.subject.initialize(factoryAddress);
            const actual = await this.subject.factory();
            expect(factoryAddress).to.eq(actual);
        });
        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await this.deploymentFixture({ skipInit: true });
                    await expect(this.subject.connect(s).factory()).to.not.be
                        .reverted;
                });
            });
        });
    });

    describe("#initialized", () => {
        it("is false after contract creation", async () => {
            await this.deploymentFixture({ skipInit: true });
            expect(false).to.eq(await this.subject.initialized());
        });
        it("is initialized with address after #initialize is called", async () => {
            const factoryAddress = randomAddress();
            await this.deploymentFixture({ skipInit: true });
            await this.subject.initialize(factoryAddress);
            const actual = await this.subject.initialized();
            expect(true).to.eq(actual);
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(this.subject.connect(s).initialized()).to.not
                        .be.reverted;
                });
            });
        });
    });

    describe("#initialize", () => {
        it("initializes factory reference", async () => {
            const factoryAddress = randomAddress();
            await this.deploymentFixture({ skipInit: true });
            await this.subject.initialize(factoryAddress);
            const actual = await this.subject.factory();
            expect(factoryAddress).to.eq(actual);
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    const factoryAddress = randomAddress();
                    await this.deploymentFixture({ skipInit: true });
                    await expect(
                        this.subject.connect(s).initialize(factoryAddress)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases", () => {
            describe("when called second time", () => {
                it("reverts", async () => {
                    const factoryAddress = randomAddress();
                    await this.deploymentFixture({ skipInit: true });
                    await this.subject.initialize(factoryAddress);
                    await expect(
                        this.subject.initialize(factoryAddress)
                    ).to.be.revertedWith(Exceptions.INITIALIZED_ALREADY);
                });
            });
        });
    });

    describe("#deployVault", () => {
        let deployVaultFixture: Function;
        let lastNft: number;
        let nft: number;
        before(async () => {
            deployVaultFixture = deployments.createFixture(async () => {
                await this.deploymentFixture();
                lastNft = (await this.vaultRegistry.vaultsCount()).toNumber();
                const tokenAddresses = this.tokens
                    .slice(0, 2)
                    .map((x: ERC20) => x.address);
                await expect(
                    this.subject.deployVault(
                        tokenAddresses,
                        [],
                        this.ownerSigner.address
                    )
                );
                nft = (await this.vaultRegistry.vaultsCount()).toNumber();
            });
        });
        beforeEach(async () => {
            await deployVaultFixture();
        });
        it("deploys a new vault", async () => {
            const address = await this.vaultRegistry.vaultForNft(nft);
            const code = await ethers.provider.getCode(address);
            expect(code.length).to.be.gt(2);
        });

        it("registers vault with vault registry and issues nft", async () => {
            expect(nft).to.be.gt(lastNft);
        });

        it("the nft is owned by the owner from #deployVault arguments", async () => {
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
                        .setPendingParams({ ...params, permissionless: true });
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitParams();

                    await withSigner(randomAddress(), async (s) => {
                        const tokenAddresses = this.tokens
                            .slice(0, 2)
                            .map((x: ERC20) => x.address);
                        await expect(
                            this.subject
                                .connect(s)
                                .deployVault(
                                    tokenAddresses,
                                    [],
                                    this.ownerSigner.address
                                )
                        ).to.not.be.reverted;
                    });
                });
            });
            describe("when not permissionless", () => {
                beforeEach(async () => {
                    const params = await this.protocolGovernance.params();
                    await this.protocolGovernance
                        .connect(this.admin)
                        .setPendingParams({ ...params, permissionless: false });
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitParams();
                });
                it("allowed: protocol governance admin", async () => {
                    const tokenAddresses = this.tokens
                        .slice(0, 2)
                        .map((x: ERC20) => x.address);
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .deployVault(
                                tokenAddresses,
                                [],
                                this.ownerSigner.address
                            )
                    ).to.not.be.reverted;
                });
                it("denied: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        const tokenAddresses = this.tokens.map(
                            (x: ERC20) => x.address
                        );
                        await expect(
                            this.subject
                                .connect(s)
                                .deployVault(
                                    tokenAddresses,
                                    [],
                                    this.ownerSigner.address
                                )
                        ).to.be.revertedWith(
                            Exceptions.PERMISSIONLESS_OR_ADMIN
                        );
                    });
                });
            });
        });
    });

    if (delayedProtocolParams) {
        delayedProtocolParamsBehavior.call(this as any, delayedProtocolParams);
    }
}
