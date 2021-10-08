import { expect } from "chai";
import { ethers } from "hardhat";
import type * as ethersT from "ethers";


describe("VaultManagerGovernance tests", function() {
    let vaultManagerGovernance: ethersT.Contract;
    let protocolGovernance: ethersT.Contract;
    let deployer: ethersT.Signer;
    let stranger: ethersT.Signer;


    beforeEach(async function() {
        const Common = await ethers.getContractFactory("Common");
        await Common.deploy();
        const VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance");
        const ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        [deployer, stranger] = await ethers.getSigners();

        protocolGovernance = await ProtocolGovernance.deploy();
        vaultManagerGovernance = await VaultManagerGovernance.deploy(true, protocolGovernance.address);
    });

    it("Governance params should be set", async function() {
        expect(await vaultManagerGovernance.governanceParams()).to.deep.equal([true, protocolGovernance.address]);
    });
});
