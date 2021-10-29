import { expect } from "chai";
import { 
    ethers,
    deployments
} from "hardhat";
import {
    BigNumber,
    Signer,
    Contract,
    ContractFactory
} from "ethers";
import { before } from "mocha";
import Exceptions from "./library/Exceptions";
import {
    decodeFromBytes,
    encodeToBytes,
    now,
    sleep, 
    sleepTo,
    toObject
} from "./library/Helpers";

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
            maxTokensPerVault: BigNumber.from(1),
            governanceDelay: BigNumber.from(1),
            strategyPerformanceFee: BigNumber.from(1),
            protocolPerformanceFee: BigNumber.from(1),
            protocolExitFee: BigNumber.from(1),
            protocolTreasury: ethers.constants.AddressZero,
            vaultRegistry: ethers.constants.AddressZero
        }

        let encoded = encodeToBytes(["tuple(uint256 maxTokensPerVault, uint256 governanceDelay, uint256 strategyPerformanceFee, uint256 protocolPerformanceFee, uint256 protocolExitFee, string protocolTreasury, string vaultRegistry)"], [data]);

        it("sets", async () => {
            await testEncoding.setDataCalldata(encoded);
            expect(toObject(await testEncoding.getData())).to.deep.equal(data);
        });

        it("sets", async () => {
            let addr: string = await ((await ethers.getSigners())[0]).getAddress();
            let encoded = encodeToBytes(["string"], [addr]);
            await testEncoding.setAddress(encoded);
            expect(decodeFromBytes(["string"], encoded)).to.deep.equal([addr]);
        });
    });
});
