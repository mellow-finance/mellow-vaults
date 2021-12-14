import { BigNumber } from "@ethersproject/bignumber";
import {
    Arbitrary,
    assert,
    asyncProperty,
    AsyncPropertyHookFunction,
    bigUintN,
    hexaString,
    Parameters,
} from "fast-check";
import { ethers } from "hardhat";

export const RUNS = {
    low: 20,
    mid: 100,
    high: 500,
};

export type PropertyOptions = Parameters & {
    beforeEach?: AsyncPropertyHookFunction;
    afterEach?: AsyncPropertyHookFunction;
};

export const uint256: Arbitrary<BigNumber> = bigUintN(256).map((x: bigint) =>
    BigNumber.from(x.toString())
);

export const address: Arbitrary<string> = hexaString({
    minLength: 40,
    maxLength: 40,
}).map((x: string) => ethers.utils.getAddress(`0x${x}`));

export function pit(
    description: string,
    options: PropertyOptions,
    f: () => Promise<boolean>
): void;
export function pit<T0>(
    description: string,
    options: PropertyOptions,
    a0: Arbitrary<T0>,
    f: (c0: T0) => Promise<boolean>
): void;
export function pit<T0, T1>(
    description: string,
    options: PropertyOptions,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    f: (c0: T0, c1: T1) => Promise<boolean>
): void;
export function pit<T0, T1, T2>(
    description: string,
    options: PropertyOptions,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    a2: Arbitrary<T2>,
    f: (c0: T0, c1: T1, c2: T2) => Promise<boolean>
): void;

export function pit<T0, T1, T2, T3>(
    description: string,
    options: PropertyOptions,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    a2: Arbitrary<T2>,
    a3: Arbitrary<T3>,
    f: (c0: T0, c1: T1, c2: T2, c3: T3) => Promise<boolean>
): void;

export function pit<T0, T1, T2, T3, T4>(
    description: string,
    options: PropertyOptions,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    a2: Arbitrary<T2>,
    a3: Arbitrary<T3>,
    a4: Arbitrary<T4>,
    f: (c0: T0, c1: T1, c2: T2, c3: T3, c4: T4) => Promise<boolean>
): void;

export function pit(
    description: string,
    options: PropertyOptions,
    ...args: any[]
): void {
    it(`@property: ${description}`, async () => {
        // @ts-ignore
        let prop = asyncProperty(...args);
        if (options.beforeEach) {
            prop = prop.beforeEach(options.beforeEach);
        }
        if (options.afterEach) {
            prop = prop.afterEach(options.afterEach);
        }
        // @ts-ignore
        await assert(prop, options);
    });
}
