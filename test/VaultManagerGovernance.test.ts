import { expect } from "chai";
import { ethers } from "hardhat";
import type * as ethersT from "ethers";


describe("VaultManagerGovernance", function() {
    let ProtocolGovernance: ethersT.ContractFactory;
    let vaultManagerGovernance: ethersT.Contract;
    let protocolGovernance: ethersT.Contract;
    let deployer: ethersT.Signer;
    let stranger: ethersT.Signer;

    beforeEach(async function() {
        const Common = await ethers.getContractFactory("Common");
        await Common.deploy();
        const VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance");
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        [deployer, stranger] = await ethers.getSigners();

        protocolGovernance = await ProtocolGovernance.deploy();
        vaultManagerGovernance = await VaultManagerGovernance.deploy(true, protocolGovernance.address);
    });

    it("Governance params should be set", async () => {
        expect(await vaultManagerGovernance.governanceParams()).to.deep.equal(
            [true, protocolGovernance.address]
        );
    });

    describe("Set pending governance params test", () => {
        let newProtocolGovernance: ethersT.Contract;
    
        beforeEach(async () => {
            newProtocolGovernance = await ProtocolGovernance.deploy();
        });
    
        it("Role should be governance or delegate", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).setPendingGovernanceParams([false, newProtocolGovernance.address])
            ).to.be.revertedWith("GD");
        });

        it("Pending governance params address should not be equal to 0x0", async () => {
            let zeroAddress = ethers.constants.AddressZero;
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([false, zeroAddress])
            ).to.be.revertedWith("ZMG");
        });

        it("Should emit new event SetPendingGovernanceParams", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([false, newProtocolGovernance.address])
            ).to.emit(vaultManagerGovernance, "SetPendingGovernanceParams").withArgs([false, newProtocolGovernance.address]);
        })

        it("Pending governance params should be set", async () => {
            await vaultManagerGovernance.setPendingGovernanceParams([false, newProtocolGovernance.address]);
            expect(
                await vaultManagerGovernance.pendingGovernanceParams()
            ).to.deep.equal([false, newProtocolGovernance.address]);
        });
    });

    describe("Commit governance params test", function() {
        let newProtocolGovernance: ethersT.Contract;

        beforeEach(async () => {
            newProtocolGovernance = await ProtocolGovernance.deploy();
            await vaultManagerGovernance.setPendingGovernanceParams([true, newProtocolGovernance.address]);
        });
    
        it("Role should be governance or delegate", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).commitGovernanceParams()
            ).to.be.revertedWith("GD");
        });
        
        it("Should emit new event CommitGovernanceParams", async () => {
             await expect(
                vaultManagerGovernance.commitGovernanceParams()
            ).to.emit(vaultManagerGovernance, "CommitGovernanceParams").withArgs([true, newProtocolGovernance.address]);
        });

        it("Should commit new governance params", async () => {
            await vaultManagerGovernance.commitGovernanceParams();
            expect(
                await vaultManagerGovernance.governanceParams()
            ).to.deep.equal([true, newProtocolGovernance.address]);
        });
    });
    
});
