import { BigNumber, Contract, ethers, Signer } from "ethers";
import { Arbitrary, nat, Random } from "fast-check";
import {
    generateParams,
    randomAddress,
    sleep,
    toObject,
    withSigner,
} from "../library/Helpers";
import { address, pit, RUNS } from "../library/property";
import { equals } from "ramda";
import { expect } from "chai";
import Exceptions from "../library/Exceptions";
import { VaultGovernanceContext } from "./vaultGovernance";
import { OperatorParamsStruct } from "../types/IERC20RootVaultGovernance";

export function operatorParamsBehavior<P, S extends Contract, F>(
    this: VaultGovernanceContext<S, F>,
    paramsArb: Arbitrary<P>
) {
    let someParams: P;
    let noneParams: P;
    this.beforeEach(() => {
        ({ someParams, noneParams } = generateParams(paramsArb));
    });

    describe("#operatorParams", () => {
        it("returns operatorParams", async () => {
            await this.subject
                .connect(this.admin)
                .setOperatorParams(someParams);
            expect(
                toObject(await this.subject.operatorParams())
            ).to.be.equivalent(someParams);
        });

        describe("edge cases", () => {
            describe("when operatorParams have not been set", () => {
                it("returns zero params", async () => {
                    expect(
                        toObject(await this.subject.operatorParams())
                    ).to.be.equivalent(noneParams);
                });
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject.connect(signer).operatorParams()
                    ).to.not.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });
    });

    describe("#setOperatorParams", () => {
        it("sets new operatorParams", async () => {
            await this.subject
                .connect(this.admin)
                .setOperatorParams(someParams);
            expect(
                toObject(await this.subject.operatorParams())
            ).to.be.equivalent(someParams);
        });

        describe("properties", () => {
            pit(
                "setting new oprator params overwrites old params immediately",
                { numRuns: RUNS.verylow, endOnFailure: true },
                paramsArb,
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .setOperatorParams(someParams);
                    expect(
                        await this.subject.operatorParams()
                    ).to.be.equivalent(someParams);
                    await this.subject
                        .connect(this.admin)
                        .setOperatorParams(params);
                    expect(
                        await this.subject.operatorParams()
                    ).to.be.equivalent(params);
                    return true;
                }
            );
        });

        describe("access constrol", () => {
            it("allowed: ProtocolGovernance admin or Operator", async () => {
                await expect(
                    this.subject
                        .connect(this.admin)
                        .setOperatorParams(someParams)
                ).to.not.be.reverted;
            });
            it("denied: any other address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject.connect(s).setOperatorParams(someParams)
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
        });
    });
}
