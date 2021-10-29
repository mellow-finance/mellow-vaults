import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { encodeToBytes, decodeFromBytes, toObject } from "./library/Helpers";
import { BigNumber } from "@ethersproject/bignumber";
import { ProtocolGovernance_Params } from "./library/Types";

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

    describe("when encoding governance params", () => {
        data = {
            maxTokensPerVault: 1,
            governanceDelay: 1,
            strategyPerformanceFee: 1,
            protocolPerformanceFee: 1,
            protocolExitFee: 1,
            protocolTreasury: ethers.constants.AddressZero,
            vaultRegistry: ethers.constants.AddressZero
        }

        let encoded = encodeToBytes(["tuple(uint256 maxTokensPerVault, uint256 governanceDelay, uint256 strategyPerformanceFee, uint256 protocolPerformanceFee, uint256 protocolExitFee, string protocolTreasury, string vaultRegistry)"], [data]);

        it("sets", async () => {
            await testEncoding.setDataCalldata(encoded);
            expect(toObject(await testEncoding.getData())).to.deep.equal(data);
        });
    });
    
});
