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
import { Address } from "hardhat-deploy/dist/types";

describe("ProtocolGovernance", () => {
    let ProtocolGovernance: ContractFactory;
    let protocolGovernance: Contract;
    let deployer: Signer;
    let stranger: Signer;
    let zeroAddress: Address;

    beforeEach(async () => {
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        protocolGovernance = await ProtocolGovernance.deploy();
        [deployer, stranger] = await ethers.getSigners();
        zeroAddress = ethers.constants.AddressZero;
    });

    describe("initial values", () => {
        it("does not allow deployer to pull", async () => {
            expect(await protocolGovernance.isAllowedToPull(deployer.getAddress())).to.be.equal(false);
        });

        it("does not allow stranger to pull", async () => {
            expect(await protocolGovernance.isAllowedToPull(stranger.getAddress())).to.be.equal(false);
        });

        it("has empty pending pull allow list", async () => {
            expect((await protocolGovernance.pullAllowlist())).to.be.empty;
        });

        it("has empty pending claim allow list", async () => {
            expect((await protocolGovernance.claimAllowlist())).to.be.empty;
        });

        it("has empty pending pull allow list add", async () => {
            expect((await protocolGovernance.pendingPullAllowlistAdd())).to.be.empty;
        });

        it("has empty pending claim allow list add", async () => {
            expect((await protocolGovernance.pendingClaimAllowlistAdd())).to.be.empty;
        });

        it("does not allow deployer to claim", async () => {
            expect(await protocolGovernance.isAllowedToClaim(deployer.getAddress())).to.be.equal(false);
        });

        it("does not allow stranger to claim", async () => {
            expect(await protocolGovernance.isAllowedToClaim(stranger.getAddress())).to.be.equal(false);
        });

        describe("initial params struct values", () => {
            it("has 0 max tokens per vault", async () => {
                expect(await protocolGovernance.maxTokensPerVault()).to.be.equal(0);
            });

            it("has no governance delay", async () => {
                expect(await protocolGovernance.governanceDelay()).to.be.equal(0);
            });

            it("has no strategy performance fee", async () => {
                expect(await protocolGovernance.strategyPerformanceFee()).to.be.equal(0);
            });

            it("has no protocol performance fee", async () => {
                expect(await protocolGovernance.protocolPerformanceFee()).to.be.equal(0);
            });

            it("has no protocol exit fee", async () => {
                expect(await protocolGovernance.protocolExitFee()).to.be.equal(0);
            });

            it("has 0x0 protocol treasury", async () => {
                expect(await protocolGovernance.protocolTreasury()).to.be.equal(zeroAddress);
            })
        });

    });

});
