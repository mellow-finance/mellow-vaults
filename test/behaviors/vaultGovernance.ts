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

export type VaultGovernanceContext<S extends Contract> = TestContext<S> & {
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
    this: VaultGovernanceContext<S>,
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
    if (delayedProtocolParams) {
        delayedProtocolParamsBehavior.call(this, delayedProtocolParams);
    }
}
