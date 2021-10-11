import { expect } from "chai";
import { 
    ethers, 
    deployments
} from "hardhat";
import { 
    ContractFactory, 
    Contract, 
    Signer 
} from "ethers";
import Exceptions from "./utils/Exceptions";
import { setupLibraries, setupProtocolGovernance } from "./utils/Fixtures";


describe("VaultManagerGovernance", () => {
    let ProtocolGovernance: ContractFactory;
    let vaultManagerGovernance: Contract;
    let protocolGovernance: Contract;
    let deployer: Signer;
    let stranger: Signer;

    beforeEach(async () => {
        const Common = await ethers.getContractFactory("Common");
        await Common.deploy();
        const VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance");
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        [deployer, stranger] = await ethers.getSigners();

        protocolGovernance = await ProtocolGovernance.deploy();
        vaultManagerGovernance = await VaultManagerGovernance.deploy(true, protocolGovernance.address);
    });

    it("governance params should be set", async () => {
        expect(await vaultManagerGovernance.governanceParams()).to.deep.equal(
            [true, protocolGovernance.address]
        );
    });

    describe("set pending params", () => {
        let newProtocolGovernance: Contract;
    
        beforeEach(async () => {
            newProtocolGovernance = await ProtocolGovernance.deploy();
        });
    
        it("role should be governance or delegate", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).setPendingGovernanceParams([
                    false, newProtocolGovernance.address
                ])
            ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE);
        });

        it("pending governance params address should not be equal to 0x0", async () => {
            let zeroAddress = ethers.constants.AddressZero;
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([false, zeroAddress])
            ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE_ADDRESS_ZERO);
        });

        it("should emit new event SetPendingGovernanceParams", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([false, newProtocolGovernance.address])
            ).to.emit(vaultManagerGovernance, "SetPendingGovernanceParams").withArgs([
                false, 
                newProtocolGovernance.address
            ]);
        })

        it("pending governance params should be set", async () => {
            await vaultManagerGovernance.setPendingGovernanceParams([
                false, newProtocolGovernance.address
            ]);
            expect(
                await vaultManagerGovernance.pendingGovernanceParams()
            ).to.deep.equal([false, newProtocolGovernance.address]);
        });
    });

    describe("commit governance params", () => {
        let newProtocolGovernance: Contract;

        beforeEach(async () => {
            newProtocolGovernance = await ProtocolGovernance.deploy();
            await vaultManagerGovernance.setPendingGovernanceParams([
                true, 
                newProtocolGovernance.address
            ]);
        });
    
        it("role should be governance or delegate", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).commitGovernanceParams()
            ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE);
        });
        
        it("should emit new event CommitGovernanceParams", async () => {
             await expect(
                vaultManagerGovernance.commitGovernanceParams()
            ).to.emit(vaultManagerGovernance, "CommitGovernanceParams").withArgs([
                true, 
                newProtocolGovernance.address
            ]);
        });

        it("should commit new governance params", async () => {
            await vaultManagerGovernance.commitGovernanceParams();
            expect(
                await vaultManagerGovernance.governanceParams()
            ).to.deep.equal([true, newProtocolGovernance.address]);
        });
    });
    
});
