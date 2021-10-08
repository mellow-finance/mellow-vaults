import { expect } from "chai";
import { ethers } from "hardhat";
import type * as ethersT from "ethers";

describe("Common", () => {
    let commonMock: ethersT.Contract;

    const addresses = [
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "0x0000000000000000000000000000000000000003",
        "0x0000000000000000000000000000000000000004",
        "0x0000000000000000000000000000000000000005",
        "0x0000000000000000000000000000000000000006",
        "0x0000000000000000000000000000000000000007",
        "0x0000000000000000000000000000000000000008",
        "0x0000000000000000000000000000000000000009",
        "0x000000000000000000000000000000000000000a",
        "0x000000000000000000000000000000000000000b",
        "0x000000000000000000000000000000000000000c",
        "0x000000000000000000000000000000000000000d",
        "0x000000000000000000000000000000000000000e",
        "0x000000000000000000000000000000000000000f",
    ];
    
    beforeEach(async () => {
        const Common: ethersT.ContractFactory = await ethers.getContractFactory("Common");
        await Common.deploy();
        const CommonMock: ethersT.ContractFactory = await ethers.getContractFactory("CommonMock");
        commonMock = await CommonMock.deploy();
    });

    describe("bubbleSort", () => {
        it("Should sort an array", async () => {
            const array: Array<string> = [
                addresses[3], 
                addresses[2], 
                addresses[1]
            ];
            const sorted: Array<string> = await commonMock.bubbleSort(array);
            expect(sorted).to.deep.equal([
                addresses[1], 
                addresses[2], 
                addresses[3]
            ]);
        });

        it("Should sort an array with duplicates", async () => {
            const array: Array<string> = [
                addresses[3], 
                addresses[2], 
                addresses[1], 
                addresses[2],
                addresses[3]
            ];
            const sorted: Array<string> = await commonMock.bubbleSort(array);
            expect(sorted).to.deep.equal([
                addresses[1], 
                addresses[2], 
                addresses[2], 
                addresses[3], 
                addresses[3]
            ]);
        });

        it("Should sort not fail on empty array", async () => {
            expect(await commonMock.bubbleSort([])).to.deep.equal([]);
        });
        
    });

    describe("isSortedAndUnique", () => {
        // todo
    });

    describe("projectTokenAmounts", () => {
        // todo
    });

    describe("splitAmounts", () => {
        // todo
    });
});
