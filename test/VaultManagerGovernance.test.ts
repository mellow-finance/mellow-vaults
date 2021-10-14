import { expect } from "chai";
import { 
    ethers,
    network
} from "hardhat";
import { 
    ContractFactory, 
    Contract, 
    Signer 
} from "ethers";
import Exceptions from "./utils/Exceptions";


describe("VaultManagerGovernance", () => {
    let ProtocolGovernance: ContractFactory;
    let vaultManagerGovernance: Contract;
    let protocolGovernance: Contract;
    let deployer: Signer;
    let stranger: Signer;
    let timestamp: number;

    beforeEach(async () => {
        const Common = await ethers.getContractFactory("Common");
        await Common.deploy();
        const VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance");
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        [deployer, stranger] = await ethers.getSigners();

        protocolGovernance = await ProtocolGovernance.deploy(deployer.getAddress());
        vaultManagerGovernance = await VaultManagerGovernance.deploy(true, protocolGovernance.address);
    });

    describe("governanceParams", () => {
        it("governance params", async () => {
            expect(await vaultManagerGovernance.governanceParams()).to.deep.equal(
                [true, protocolGovernance.address]
            );
        });
    });

    describe("setPendingGovernanceParams", () => {
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

        it("address should not be 0x00", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([false, ethers.constants.AddressZero])
            ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE_ADDRESS_ZERO);
        });

        it("sets correct pending timestamp", async () => {
            let customProtocol = await ProtocolGovernance.deploy();
            await customProtocol.setPendingParams([1, 0, 1, 1, 1, ethers.constants.AddressZero]);
            await customProtocol.commitParams();

            timestamp = Math.ceil(new Date().getTime() / 1000) + 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await vaultManagerGovernance.setPendingGovernanceParams([false, customProtocol.address]);
            expect(
                Math.abs(await vaultManagerGovernance.pendingGovernanceParamsTimestamp() - timestamp)
            ).to.be.lessThanOrEqual(10);
        });

        it("emits event SetPendingGovernanceParams", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([false, newProtocolGovernance.address])
            ).to.emit(vaultManagerGovernance, "SetPendingGovernanceParams").withArgs([
                false, 
                newProtocolGovernance.address
            ]);
        })

        it("sets pending params", async () => {
            await vaultManagerGovernance.setPendingGovernanceParams([
                false, newProtocolGovernance.address
            ]);
            expect(
                await vaultManagerGovernance.pendingGovernanceParams()
            ).to.deep.equal([false, newProtocolGovernance.address]);
        });
    });

    describe("commitGovernanceParams", () => {
        let newProtocolGovernance: Contract;
        let customProtocol: Contract;

        beforeEach(async () => {
            newProtocolGovernance = await ProtocolGovernance.deploy();
            await vaultManagerGovernance.setPendingGovernanceParams([
                true, 
                newProtocolGovernance.address
            ]);
            customProtocol = await ProtocolGovernance.deploy();
        });
    
        it("role should be governance or delegate", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).commitGovernanceParams()
            ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE);
        });
        
        it("waits governance delay", async () => {
            const timeout = 10**4;
            await customProtocol.setPendingParams([1, timeout, 1, 1, 1, ethers.constants.AddressZero]);
            await customProtocol.commitParams();

            timestamp += 10 ** 3;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send("evm_mine");

            await vaultManagerGovernance.setPendingGovernanceParams([false, customProtocol.address]);
            await vaultManagerGovernance.commitGovernanceParams();

            let additionalProtocol = await ProtocolGovernance.deploy();
            await vaultManagerGovernance.setPendingGovernanceParams([false, additionalProtocol.address]);
            await expect(
                vaultManagerGovernance.commitGovernanceParams()
            ).to.be.revertedWith(Exceptions.TIMESTAMP);
        });
        
        it("emits CommitGovernanceParams", async () => {
             await expect(
                vaultManagerGovernance.commitGovernanceParams()
            ).to.emit(vaultManagerGovernance, "CommitGovernanceParams").withArgs([
                true,
                newProtocolGovernance.address
            ]);
        });

        it("commits new governance params", async () => {
            await vaultManagerGovernance.commitGovernanceParams();
            expect(
                await vaultManagerGovernance.governanceParams()
            ).to.deep.equal([true, newProtocolGovernance.address]);
        });
    });
    
});
