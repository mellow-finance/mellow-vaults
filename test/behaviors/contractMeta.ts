import { expect } from "chai";
import { Contract } from "ethers";
import { TestContext } from "../library/setup";
import { decodeFromBytes, randomAddress, withSigner } from "../library/Helpers";
export type ContractMetaContext<S extends Contract, F> = TestContext<S, F>;

export function ContractMetaBehaviour<S extends Contract>(
    this: ContractMetaContext<S, any>,
    {
        contractName,
        contractVersion,
    }: { contractName: string; contractVersion: string }
) {
    describe("#contractName", () => {
        it("returns contract name string", async () => {
            await withSigner(randomAddress(), async (signer) => {
                expect(
                    await this.subject.connect(signer).contractName()
                ).to.be.eq(contractName);
            });
        });
    });

    describe("#contractNameBytes", () => {
        it("returns contract name bytes", async () => {
            let nameBuffer = Buffer.from(contractName);
            let nameVersionBytes = "0x" + nameBuffer.toString("hex");
            let nameVersionBytes32 = nameVersionBytes.padEnd(66, "0");

            await withSigner(randomAddress(), async (signer) => {
                expect(
                    await this.subject.connect(signer).contractNameBytes()
                ).to.be.eq(nameVersionBytes32);
            });
        });
    });

    describe("#contractVersion", () => {
        it("returns contract name string", async () => {
            await withSigner(randomAddress(), async (signer) => {
                expect(
                    await this.subject.connect(signer).contractVersion()
                ).to.be.eq(contractVersion);
            });
        });
    });

    describe("#contractVersionBytes", () => {
        it("returns contract name bytes", async () => {
            let versionBuffer = Buffer.from(contractVersion);
            let contractVersionBytes = "0x" + versionBuffer.toString("hex");
            let contractVersionBytes32 = contractVersionBytes.padEnd(66, "0");

            await withSigner(randomAddress(), async (signer) => {
                expect(
                    await this.subject.connect(signer).contractVersionBytes()
                ).to.be.eq(contractVersionBytes32);
            });
        });
    });
}
