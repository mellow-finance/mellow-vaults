import { expect } from "chai";
import { ethers } from "hardhat";
import { 
    ContractFactory, 
    Contract, 
    Signer 
} from "ethers";
import Exceptions from "./library/Exceptions";
import {
    setupERC20VaultFactory,
    setupProtocolGovernance,
    setupVaultManagerGovernance,
} from "./library/Fixtures";
import { sleepTo } from "./library/Helpers";


describe("VaultManagerGovernance", () => {
    let ProtocolGovernance: ContractFactory;
    let ERC20VaultFactory: ContractFactory;
    let vaultManagerGovernance: Contract;
    let protocolGovernance: Contract;
    let newProtocolGovernance: Contract;
    let erc20VaultFactory: Contract;
    let deployer: Signer;
    let stranger: Signer;
    let timestamp: number;

    before(async () => {
        [deployer, stranger] = await ethers.getSigners();

        erc20VaultFactory = await setupERC20VaultFactory({
            params: {
                owner: deployer
            }
        });

        protocolGovernance = await setupProtocolGovernance({
            params: {
                owner: deployer
            },
            admin: deployer
        });

        newProtocolGovernance = await setupProtocolGovernance({
            params: {
                owner: deployer
            },
            admin: deployer
        });

        vaultManagerGovernance = await setupVaultManagerGovernance({
            params: {
                owner: deployer
            },
            admin: deployer,
            permissionless: true,
            protocolGovernance: protocolGovernance,
            factory: erc20VaultFactory
        });

        // await setupCommonLibrary();

        [deployer, stranger] = await ethers.getSigners();
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        console.log("protocol governance address", protocolGovernance.address);
        console.log("vault factory address", erc20VaultFactory.address);
    })

    // beforeEach(async () => {
    //     const Common = await ethers.getContractFactory("Common");
    //     await Common.deploy();
    //     const VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance");
    //     ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");

    // });

    describe("governanceParams", () => {
        it("governance params", async () => {
            expect(await vaultManagerGovernance.governanceParams()).to.deep.equal(
                [
                    true, 
                    protocolGovernance.address, 
                    erc20VaultFactory.address
                ]
            );
        });
    });

    describe("setPendingGovernanceParams", () => {
    
        it("role should be governance or delegate", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).setPendingGovernanceParams([
                    false, 
                    newProtocolGovernance.address, 
                    erc20VaultFactory.address
                ])
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("governance params address should not be zero", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([
                    false, ethers.constants.AddressZero, erc20VaultFactory.address
                ])
            ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE_ADDRESS_ZERO);
        });

        it("factory address should not be zero", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([
                    false, protocolGovernance.address, ethers.constants.AddressZero,
                ])
            ).to.be.revertedWith(Exceptions.VAULT_FACTORY_ADDRESS_ZERO);
        })

        it("sets correct pending timestamp", async () => {
            let customProtocol = await ProtocolGovernance.deploy(await deployer.getAddress());
            await customProtocol.setPendingParams([1, 0, 1, 1, 1, ethers.constants.AddressZero]);
            await customProtocol.commitParams();

            timestamp = Math.ceil(new Date().getTime() / 1000) + 10**6;
            await sleepTo(timestamp);

            await vaultManagerGovernance.setPendingGovernanceParams([
                false, customProtocol.address, erc20VaultFactory.address
            ]);
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
            ).to.deep.equal([
                false, newProtocolGovernance.address, erc20VaultFactory.address
            ]);
        });
    });

    describe("commitGovernanceParams", () => {
        let newProtocolGovernance: Contract;
        let customProtocol: Contract;

        beforeEach(async () => {
            newProtocolGovernance = await ProtocolGovernance.deploy(deployer.getAddress());
            await vaultManagerGovernance.setPendingGovernanceParams([
                true, 
                newProtocolGovernance.address,
                erc20VaultFactory.address
            ]);
            customProtocol = await ProtocolGovernance.deploy(deployer.getAddress());
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
            await sleepTo(timestamp);

            await vaultManagerGovernance.setPendingGovernanceParams([false, customProtocol.address]);
            await vaultManagerGovernance.commitGovernanceParams();

            let additionalProtocol = await ProtocolGovernance.deploy(deployer.getAddress());
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
                newProtocolGovernance.address,
                erc20VaultFactory.address
            ]);
        });

        it("commits new governance params", async () => {
            await vaultManagerGovernance.commitGovernanceParams();
            expect(
                await vaultManagerGovernance.governanceParams()
            ).to.deep.equal([
                true, newProtocolGovernance.address, erc20VaultFactory.address
            ]);
        });
    });
    
});
