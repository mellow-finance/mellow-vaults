import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { encodeToBytes, toObject } from "./library/Helpers";

describe("TestEncoding", () => {
    let testEncoding: Contract;
    let data: any;
    let deploymentFixture: Function;

    before(async () => {
        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            let TestEncoding = await ethers.getContractFactory("TestEncoding");
            return await TestEncoding.deploy();
        });
    });

    beforeEach(async () => {
        testEncoding = await deploymentFixture();
    });

    describe("when encoding governance params", () => {
        data = {
            maxTokensPerVault: BigNumber.from(1),
            governanceDelay: BigNumber.from(2),
            strategyPerformanceFee: BigNumber.from(3),
            protocolPerformanceFee: BigNumber.from(4),
            protocolExitFee: BigNumber.from(5),
            protocolTreasury: ethers.constants.AddressZero,
            vaultRegistry: ethers.constants.AddressZero,
        };

        let encoded = encodeToBytes(
            [
                "tuple(uint256 maxTokensPerVault, uint256 governanceDelay, uint256 strategyPerformanceFee, uint256 protocolPerformanceFee, uint256 protocolExitFee, address protocolTreasury, address vaultRegistry) data",
            ],
            [data]
        );

        it("sets `bytes calldata`", async () => {
            await testEncoding.setDataCalldata(encoded);
            expect(toObject(await testEncoding.getData())).to.deep.equal(data);
        });

        it("sets `bytes memory`", async () => {
            await testEncoding.setDataMemory(encoded);
            expect(toObject(await testEncoding.getData())).to.deep.equal(data);
        });
    });
});
