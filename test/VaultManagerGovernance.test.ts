import { expect } from "chai";
import { ethers } from "hardhat";
import { Address } from "hardhat-deploy/dist/types";



describe("VaultManagerGovernance test", () => {
    let common: any
    let vaultManagerGovernance: any;
    let protocolGovernance: any;
    let deployer, stranger: any;
    let Common: any;
    let VaultManagerGovernance: any;
    let ProtocolGovernance: any;

    beforeEach(async () => {
       [deployer, stranger] = await ethers.getSigners();

        Common = await ethers.getContractFactory("Common");
        common = await Common.deploy();
        VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance");
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");

        protocolGovernance = await ProtocolGovernance.deploy();
        vaultManagerGovernance = await VaultManagerGovernance.deploy(true, protocolGovernance.address);
    });

    it("Governance params should be set", async () => {
        expect(await vaultManagerGovernance.governanceParams()).to.deep.equal(
            [true, protocolGovernance.address]
        );
    });

    describe("Set pending governance params test", () => {
        let newProtocolGovernance: any;
    
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

        it("Pending governance timestamp should be set");

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
        let newProtocolGovernance: any;

        beforeEach(async () => {
            newProtocolGovernance = await ProtocolGovernance.deploy();
            await vaultManagerGovernance.setPendingGovernanceParams([true, newProtocolGovernance.address]);
        });
    
        it("Role should be governance or delegate", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).commitGovernanceParams()
            ).to.be.revertedWith("GD");
        });
        
        it("Pending governance timestamp should be graeter than 0");
        
        it("Pending governance timestamp should be less than current block timestamp");

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
