import { BigNumber, Contract, ethers, Signer } from "ethers";
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
import { VaultGovernance } from "../types";
import { InternalParamsStructOutput } from "../types/VaultGovernance";

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

    if (delayedProtocolParams) {
        delayedProtocolParamsBehavior.call(this as any, delayedProtocolParams);
    }
}
