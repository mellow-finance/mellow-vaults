import { expect } from "chai";
import { ethers } from "hardhat";


describe("VaultManagerGovernance tests", function() {
    let common: any
    let vaultManagerGovernance: any;
    let protocolGovernance: any;


    beforeEach(async function() {
        const Common = await ethers.getContractFactory("Common");
        common = await Common.deploy();
        const VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance");
        const ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");

        protocolGovernance = await ProtocolGovernance.deploy();
        vaultManagerGovernance = await VaultManagerGovernance.deploy(true, protocolGovernance.address);
    });

    it("Governance params should be set", async function() {
        expect(await vaultManagerGovernance.governanceParams()).to.deep.equal([true, protocolGovernance.address]);
    });
});
