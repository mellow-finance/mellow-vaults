import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";

import { Address } from "./library/Types";
import { deployCommonLibraryTest } from "./library/Fixtures";

describe("Common", () => {
    let commonTest: Contract;
    const addresses: Address[] = [
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "0x0000000000000000000000000000000000000003",
        "0x0000000000000000000000000000000000000004",
    ];

    before(async () => {
        commonTest = await deployCommonLibraryTest();
    });

    describe("bubbleSort", () => {
        it("sort unsorted", async () => {
            const array: Address[] = [
                addresses[3], 
                addresses[2], 
                addresses[1]
            ];
            const sorted: Address[] = await commonTest.bubbleSort(array);
            expect(sorted).to.deep.equal([
                addresses[1], 
                addresses[2], 
                addresses[3]
            ]);
        });

        it("sort non-unique", async () => {
            const array: Address[] = [
                addresses[3], 
                addresses[2], 
                addresses[1], 
                addresses[2],
                addresses[3]
            ];
            const sorted: Address[] = await commonTest.bubbleSort(array);
            expect(sorted).to.deep.equal([
                addresses[1], 
                addresses[2], 
                addresses[2], 
                addresses[3], 
                addresses[3]
            ]);
        });

        it("sort empty array", async () => {
            expect(await commonTest.bubbleSort([])).to.deep.equal([]);
        });
        
    });

    describe("isSortedAndUnique", () => {
        it("true for sorted and unique", async () => {
            const array: Address[] = [
                addresses[1], 
                addresses[2], 
                addresses[3]
            ];
            expect(await commonTest.isSortedAndUnique(array)).to.equal(true);
        });

        it("false for unsorted", async () => {
            const array: Address[] = [
                addresses[3], 
                addresses[1], 
                addresses[2]
            ];
            expect(await commonTest.isSortedAndUnique(array)).to.equal(false);
        });

        it("false for unsorted and non-unique", async () => {
            const array: Address[] = [
                addresses[3], 
                addresses[1], 
                addresses[2], 
                addresses[3]
            ];
            expect(await commonTest.isSortedAndUnique(array)).to.equal(false);
        });

        it("false for sorted an non-unique", async () => {
            const array: Address[] = [
                addresses[0],
                addresses[1],
                addresses[1],
                addresses[3]
            ];
            expect(await commonTest.isSortedAndUnique(array)).to.equal(false);
        });

        it("true for empty", async () => {
            expect(await commonTest.isSortedAndUnique([])).to.equal(true);
        });
    });

    describe("projectTokenAmounts", () => {
        // todo
    });

    describe("splitAmounts", () => {
        // todo
    });
});
