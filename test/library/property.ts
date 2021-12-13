import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, bigIntN, bigUintN, hexaString } from "fast-check";

export const uint256: Arbitrary<BigNumber> = bigUintN(256).map((x: bigint) =>
    BigNumber.from(x.toString())
);

export const address: Arbitrary<string> = hexaString({ maxLength: 40 }).map(
    (x: string) => `0x${x}`
);

export function pit(description: string, f: () => Promise<boolean>): void;
export function pit<T0>(
    description: string,
    a0: Arbitrary<T0>,
    f: (c0: T0) => Promise<boolean>
): void;
export function pit<T0, T1>(
    description: string,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    f: (c0: T0, c1: T1) => Promise<boolean>
): void;
export function pit<T0, T1, T2>(
    description: string,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    a2: Arbitrary<T2>,
    f: (c0: T0, c1: T1, c2: T2) => Promise<boolean>
): void;

export function pit<T0, T1, T2, T3>(
    description: string,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    a2: Arbitrary<T2>,
    a3: Arbitrary<T3>,
    f: (c0: T0, c1: T1, c2: T2, c3: T3) => Promise<boolean>
): void;

export function pit<T0, T1, T2, T3, T4>(
    description: string,
    a0: Arbitrary<T0>,
    a1: Arbitrary<T1>,
    a2: Arbitrary<T2>,
    a3: Arbitrary<T3>,
    a4: Arbitrary<T4>,
    f: (c0: T0, c1: T1, c2: T2, c3: T3, c4: T4) => Promise<boolean>
): void;

export function pit(description: string, ...args: any[]): void {
    it(`@property: ${description}`, async () => {
        // @ts-ignore
        await fc.assert(fc.asyncProperty(...args));
    });
}
