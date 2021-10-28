import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { encodeToBytes, decodeFromBytes } from "./library/Helpers";
import { BigNumber } from "@ethersproject/bignumber";

describe("TestEncoding", () => {
    let TestEncoding: ContractFactory;
    let testEncoding: Contract;
    let data: any;

    before(async () => {
        TestEncoding = await ethers.getContractFactory("TestEncoding");
    }); 

    beforeEach(async () => {
        testEncoding = await TestEncoding.deploy();
    });

    describe("when encoding primitive types", () => {
        describe("when data === integer", () => {
            it("sets", async () => {
                data = encodeToBytes(
                    ["uint"],
                    [1]
                );
                await testEncoding.setData(data);
                expect(
                    decodeFromBytes(
                        ["int"],
                        await testEncoding.getData()
                    )
                ).to.deep.equal([BigNumber.from(1)]);
            }); 
        });
        describe("when data === string", () => {
            it("sets", async () => {
                data = encodeToBytes(
                    ["string"],
                    ["abc"]
                );
                await testEncoding.setData(data);
                expect(
                    decodeFromBytes(
                        ["string"],
                        await testEncoding.getData()
                    )
                ).to.deep.equal(["abc"]);
            }); 
        });
    });


    describe("when encoding complex types", () => {
        describe("when data === struct", () => {
            it("sets", async () => {
                data = encodeToBytes(
                    [ "uint a", "tuple(uint256 b, string c) d" ],
                    [
                        123,
                        { b: 123, c: "Hello World" }
                    ]
                );
                await testEncoding.setData(data);
                expect(
                    decodeFromBytes(
                        [ "uint a", "tuple(uint256 b, string c) d" ],
                        await testEncoding.getData()
                    )
                ).to.deep.equal([
                    BigNumber.from(123),
                    [
                        BigNumber.from(123),
                        'Hello World'
                    ]
                ]);
            }); 
        });
    });
});
