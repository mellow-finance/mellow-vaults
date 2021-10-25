import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { 
    Contract,
    Signer 
} from "ethers";
import Exceptions from "./library/Exceptions";
import {
    deployERC20VaultFactory,
    deployProtocolGovernance,
    deployVaultGovernanceFactory,
    deployVaultManagerGovernance,
} from "./library/Deployments";
import {
    ProtocolGovernance,
    ERC20VaultFactory,
    VaultManagerGovernance,
    ProtocolGovernance_Params,
    ProtocolGovernance_constructorArgs,
    VaultGovernanceFactory,
    VaultManagerGovernance_constructorArgs,
} from "./library/Types";
import { 
    sleep, 
    sleepTo,
    now,
    toObject
} from "./library/Helpers";
import { BigNumber } from "@ethersproject/bignumber";


describe("VaultManagerGovernance", () => {
    let vaultManagerGovernance: VaultManagerGovernance;
    let protocolGovernance: ProtocolGovernance;
    let deployer: Signer;
    let stranger: Signer;
    let timestamp: number;
    let timeShift: number;
    let deploymentFixture: Function;
    let constructorArgs: VaultManagerGovernance_constructorArgs;
    let newProtocolGovernance: ProtocolGovernance;
    let ERC20VaultFactory: ERC20VaultFactory;
    let vaultGovernanceFactory: VaultGovernanceFactory;
    let protocolTreasury: Signer;
    let gatewayVaultManager: Signer;

    before(async () => {
        [deployer, stranger, protocolTreasury, gatewayVaultManager] = await ethers.getSigners();
        timeShift = 10**10;
        timestamp = now() + timeShift;
        sleepTo(timestamp);
        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();

            newProtocolGovernance = await deployProtocolGovernance();
            protocolGovernance = await deployProtocolGovernance();
            ERC20VaultFactory = await deployERC20VaultFactory();
            vaultGovernanceFactory = await deployVaultGovernanceFactory();

            constructorArgs = {
                permissionless: true,
                protocolGovernance: protocolGovernance.address,
                governanceFactory: vaultGovernanceFactory.address,
                factory: ERC20VaultFactory.address
            }

            return await deployVaultManagerGovernance({
                constructorArgs: constructorArgs,
                adminSigner: deployer
            });
        });
    });

    beforeEach(async () => {
        vaultManagerGovernance = await deploymentFixture();
    });

    describe("governanceParams", () => {
        it("passes", async () => {
            expect(
                toObject(await vaultManagerGovernance.governanceParams())
            ).to.deep.equal(constructorArgs);
        });
    });

    describe("setPendingGovernanceParams", () => {
        it("role should be governance or delegate", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([ethers.constants.AddressZero]);
            await expect(
                vaultManagerGovernance.connect(stranger).setPendingGovernanceParams([
                    false, 
                    protocolGovernance.address, 
                    ERC20VaultFactory.address,
                    vaultGovernanceFactory.address,
                ])
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("governance params address should not be zero", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([
                    false,
                    ethers.constants.AddressZero, 
                    ERC20VaultFactory.address, 
                    vaultGovernanceFactory.address
                ])
            ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE_ADDRESS_ZERO);
        });

        it("factory address should not be zero", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([
                    false, 
                    protocolGovernance.address, 
                    ethers.constants.AddressZero, 
                    vaultGovernanceFactory.address,
                ])
            ).to.be.revertedWith(Exceptions.VAULT_FACTORY_ADDRESS_ZERO);
        })

        it("sets correct pending timestamp", async () => {
            let customProtocol = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await deployer.getAddress(),
                },
                initializerArgs: {
                    params:  {
                        maxTokensPerVault: BigNumber.from(2),
                        governanceDelay: BigNumber.from(0),
                        strategyPerformanceFee: BigNumber.from(10 ** 9),
                        protocolPerformanceFee: BigNumber.from(10 ** 9),
                        protocolExitFee: BigNumber.from(10 ** 9),
                        protocolTreasury: await protocolTreasury.getAddress(),
                        gatewayVaultManager: await gatewayVaultManager.getAddress()
                    }
                },
                adminSigner: deployer
            });
            await customProtocol.setPendingParams({
                maxTokensPerVault: 2,
                governanceDelay: 0,
                strategyPerformanceFee: 0,
                protocolPerformanceFee: 1,
                protocolExitFee: 1,
                protocolTreasury: ethers.constants.AddressZero,
                gatewayVaultManager: ethers.constants.AddressZero
            });
            await customProtocol.commitParams();

            timestamp += 10**6
            sleepTo(timestamp);

            await vaultManagerGovernance.setPendingGovernanceParams([
                false, customProtocol.address, ERC20VaultFactory.address, vaultGovernanceFactory.address,
            ]);
            expect(
                Math.abs(await vaultManagerGovernance.pendingGovernanceParamsTimestamp() - timestamp)
            ).to.be.lessThanOrEqual(10);
        });

        it("emits event SetPendingGovernanceParams", async () => {
            await expect(
                vaultManagerGovernance.setPendingGovernanceParams([                    
                    false, 
                    newProtocolGovernance.address, 
                    ERC20VaultFactory.address,
                    vaultGovernanceFactory.address,
                ])
            ).to.emit(vaultManagerGovernance, "SetPendingGovernanceParams").withArgs([
                false,
                newProtocolGovernance.address
            ]);
        })

        it("sets pending params", async () => {
            await vaultManagerGovernance.setPendingGovernanceParams([
                false,
                newProtocolGovernance.address,
                ERC20VaultFactory.address,
                vaultGovernanceFactory.address,
            ]);
            expect(
                await vaultManagerGovernance.pendingGovernanceParams()
            ).to.deep.equal([
                false,
                newProtocolGovernance.address,
                ERC20VaultFactory.address,
                vaultGovernanceFactory.address,
            ]);
        });
    });

     describe("commitGovernanceParams", () => {
        let customProtocol: Contract;

        beforeEach(async () => {
            customProtocol = await deployProtocolGovernance({
                adminSigner: deployer
            });
        });
    
        it("role should be admin", async () => {
            await expect(
                vaultManagerGovernance.connect(stranger).commitGovernanceParams()
            ).to.be.revertedWith(Exceptions.ADMIN);
        });
        
        it("waits governance delay", async () => {
            const timeout: number = 10000;
            await customProtocol.setPendingParams({
                maxTokensPerVault: 2,
                governanceDelay: 0,
                strategyPerformanceFee: 0,
                protocolPerformanceFee: 1,
                protocolExitFee: 1,
                protocolTreasury: ethers.constants.AddressZero,
                gatewayVaultManager: ethers.constants.AddressZero
            });

            await customProtocol.commitParams();

            let newERC20VaultFactory = await deployERC20VaultFactory();
            let newVaultGovernanceFactory = await deployVaultGovernanceFactory();

            newProtocolGovernance = await deployProtocolGovernance({
                adminSigner: deployer,
                constructorArgs: {
                    admin: await deployer.getAddress()
                },
                initializerArgs: {
                    params: {
                        maxTokensPerVault: BigNumber.from(2),
                        governanceDelay: BigNumber.from(100),
                        strategyPerformanceFee: BigNumber.from(10 ** 9),
                        protocolPerformanceFee: BigNumber.from(10 ** 9),
                        protocolExitFee: BigNumber.from(10 ** 9),
                        protocolTreasury: await protocolTreasury.getAddress(),
                        gatewayVaultManager: await gatewayVaultManager.getAddress()
                    }
                }
            });

            await vaultManagerGovernance.setPendingGovernanceParams({
                permissionless: false, 
                protocolGovernance: newProtocolGovernance.address, 
                factory: newERC20VaultFactory.address,
                governanceFactory: newVaultGovernanceFactory.address,
            });

            await vaultManagerGovernance.commitGovernanceParams()

            await vaultManagerGovernance.setPendingGovernanceParams({
                permissionless: false, 
                protocolGovernance: customProtocol.address, 
                factory: newERC20VaultFactory.address,
                governanceFactory: newVaultGovernanceFactory.address,
            });
            await expect(
                vaultManagerGovernance.commitGovernanceParams()
            ).to.be.revertedWith(Exceptions.TIMESTAMP);

            timestamp += timeout;
            await sleep(timeout);
            await expect(vaultManagerGovernance.commitGovernanceParams()).to.not.be.reverted;
        });
        
        it("emits CommitGovernanceParams", async () => {
            const timeout: number = 10000;
            await vaultManagerGovernance.setPendingGovernanceParams({
                permissionless: false, 
                protocolGovernance: protocolGovernance.address, 
                factory: ERC20VaultFactory.address,
                governanceFactory: vaultGovernanceFactory.address,
            });

            await sleep(timeout);

             await expect(
                vaultManagerGovernance.commitGovernanceParams()
            ).to.emit(vaultManagerGovernance, "CommitGovernanceParams").withArgs([
                false,
                protocolGovernance.address,
                ERC20VaultFactory.address
            ]);
        });

        it("commits new governance params", async () => {
            newProtocolGovernance = await deployProtocolGovernance({
                adminSigner: deployer,
                constructorArgs: {
                    admin: await deployer.getAddress()
                },
                initializerArgs: {
                    params: {
                        maxTokensPerVault: BigNumber.from(2),
                        governanceDelay: BigNumber.from(100),
                        strategyPerformanceFee: BigNumber.from(10 ** 9),
                        protocolPerformanceFee: BigNumber.from(10 ** 9),
                        protocolExitFee: BigNumber.from(10 ** 9),
                        protocolTreasury: await protocolTreasury.getAddress(),
                        gatewayVaultManager: await gatewayVaultManager.getAddress()
                    }
                }
            });

            await vaultManagerGovernance.setPendingGovernanceParams({
                permissionless: false, 
                protocolGovernance: newProtocolGovernance.address, 
                factory: ERC20VaultFactory.address,
                governanceFactory: vaultGovernanceFactory.address,
            });

            await vaultManagerGovernance.commitGovernanceParams();
            expect(
                await vaultManagerGovernance.governanceParams()
            ).to.deep.equal([
                false, 
                newProtocolGovernance.address, 
                ERC20VaultFactory.address, 
                vaultGovernanceFactory.address
            ]);
        });
    });    
});
