import { expect } from "chai";
import { 
    ethers,
    network,
    deployments
} from "hardhat";
import {
    BigNumber,
    Signer
} from "ethers";
import { before } from "mocha";
import Exceptions from "./library/Exceptions";
import {
    setTimestamp,
    sleep, 
    sleepTo
} from "./library/Helpers";
import { 
    deployLpIssuerGovernance,
    deployProtocolGovernance 
} from "./library/Deployments";
import { LpIssuerGovernance, 
    ProtocolGovernance, 
    ProtocolGovernance_Params,
    LpIssuerGovernance_constructorArgs,
    ProtocolGovernance_constructorArgs
 } from "./library/Types";


describe("LpIssuerGovernance", () => {
    let contract: LpIssuerGovernance;
    let protocol: ProtocolGovernance;
    let constructorArgs: LpIssuerGovernance_constructorArgs;
    let temporaryParams: LpIssuerGovernance_constructorArgs; 
    let emptyParams: LpIssuerGovernance_constructorArgs;
    let temporaryProtocol: ProtocolGovernance;
    let protocolConstructorArgs: ProtocolGovernance_constructorArgs;
    let timestamp: number;
    let timeout: number;
    let timeEps: number;
    let deploymentFixture: Function;
    let deployer: Signer;
    let stranger: Signer;
    let user: Signer;

    before(async () => {
        [deployer, stranger, user] = await ethers.getSigners();
        timeout = 5;
        timeEps = 2;
        timestamp = setTimestamp() + 10**2;

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            
            emptyParams = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: ethers.constants.AddressZero
            };

            protocolConstructorArgs = {
                admin: await deployer.getAddress(),
                params: {
                    maxTokensPerVault: 1,
                    governanceDelay: 1,
                    strategyPerformanceFee: 1,
                    protocolPerformanceFee: 1,
                    protocolExitFee: 1,
                    protocolTreasury: ethers.constants.AddressZero,
                    gatewayVaultManager: ethers.constants.AddressZero
                }
            }
            protocol = await deployProtocolGovernance({
                constructorArgs: protocolConstructorArgs,
                adminSigner: deployer
            });

            constructorArgs = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: protocol.address
            };
            return deployLpIssuerGovernance({constructorArgs});
        });
    });

    beforeEach(async () => {
        contract = await deploymentFixture();
    });

    describe("constructor", () => {
        describe("governanceParams", () => {
            it("sets", async () => {
                expect(
                    await contract.governanceParams()
                ).to.deep.equal([
                    constructorArgs.gatewayVault, 
                    constructorArgs.protocolGovernance
                ]);
            });
        });
        
        describe("pendingGovernanceParams", () => {
            it("is empty", async () => {
                expect(
                    await contract.pendingGovernanceParams()
                ).to.deep.equal([
                    ethers.constants.AddressZero,
                    ethers.constants.AddressZero
                ]);
            });
        });
        
        describe("pendingGovernanceParamsTimestamp", () => {
            it("is zero", async () => {
                expect(
                    await contract.pendingGovernanceParamsTimestamp()
                ).to.deep.equal(BigNumber.from(0));
            }); 
        }); 
    });

    describe("setPendingGovernanceParams", () => {
        it("sets pending params", async () => {
            temporaryProtocol = await deployProtocolGovernance();
            temporaryParams = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: temporaryProtocol.address
            };

            await contract.setPendingGovernanceParams(temporaryParams);
            expect(
                await contract.pendingGovernanceParams()
            ).to.deep.equal([
                temporaryParams.gatewayVault,
                temporaryParams.protocolGovernance
            ]);
        });

        it("sets params timestamp", async () => {
            await sleepTo(timestamp);
            let newGovernanceParams = {
                maxTokensPerVault: 1,
                governanceDelay: timeout,
                strategyPerformanceFee: 1,
                protocolPerformanceFee: 1,
                protocolExitFee: 1,
                protocolTreasury: ethers.constants.AddressZero,
                gatewayVaultManager: ethers.constants.AddressZero,
            };
            temporaryProtocol = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await deployer.getAddress(),
                    params: newGovernanceParams
                },
                adminSigner: deployer
            });
            temporaryParams = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: temporaryProtocol.address
            };
            await contract.setPendingGovernanceParams(temporaryParams);
            expect(
                Math.abs(await contract.pendingGovernanceParamsTimestamp() - (timestamp + timeout))
            ).to.be.lessThanOrEqual(timeEps);
        });

        it("emits SetPendingGovernanceParams", async () => {
            temporaryProtocol = await deployProtocolGovernance();
            temporaryParams = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: temporaryProtocol.address
            };
            await expect(
                contract.setPendingGovernanceParams(temporaryParams)
            ).to.emit(
                contract, 
                "SetPendingGovernanceParams"
            ).withArgs([
                temporaryParams.gatewayVault,
                temporaryParams.protocolGovernance
            ]);
        });

        describe("when called by not admin", () => {
            it("reverts", async () => {
                await expect(
                    contract.connect(stranger).setPendingGovernanceParams(temporaryParams)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when address of protocolGovernance is 0x0", () => {
            it("reverts", async () => {
                await expect(
                    contract.setPendingGovernanceParams(emptyParams)
                ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE_ADDRESS_ZERO);
            });
        });
    });

    describe("commitGovernanceParams", () => {
        it("commits params", async () => {
            timestamp += 10**6;
            await sleepTo(timestamp);
            let newGovernanceParams = {
                maxTokensPerVault: 5,
                governanceDelay: timeout,
                strategyPerformanceFee: 6,
                protocolPerformanceFee: 7,
                protocolExitFee: 8,
                protocolTreasury: ethers.constants.AddressZero,
                gatewayVaultManager: ethers.constants.AddressZero,
            };
            temporaryProtocol = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await deployer.getAddress(),
                    params: newGovernanceParams
                },
                adminSigner: deployer
            });
            temporaryParams = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: temporaryProtocol.address
            };
            await contract.setPendingGovernanceParams(temporaryParams);
            await sleep(timeout);

            await contract.commitGovernanceParams();
            expect(
                await contract.governanceParams()
            ).to.deep.equal([
                temporaryParams.gatewayVault,
                temporaryParams.protocolGovernance
            ]);
        });

        it("emits CommitGovernanceParams", async () => {
            timestamp += 10**6;
            await sleepTo(timestamp);
            let newGovernanceParams = {
                maxTokensPerVault: 9,
                governanceDelay: timeout,
                strategyPerformanceFee: 10,
                protocolPerformanceFee: 11,
                protocolExitFee: 12,
                protocolTreasury: ethers.constants.AddressZero,
                gatewayVaultManager: ethers.constants.AddressZero,
            };
            temporaryProtocol = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await deployer.getAddress(),
                    params: newGovernanceParams
                },
                adminSigner: deployer
            });
            temporaryParams = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: temporaryProtocol.address
            };
            await contract.setPendingGovernanceParams(temporaryParams);
            await sleep(timeout);

            await expect(
                contract.commitGovernanceParams()
            ).to.emit(
                contract, 
                "CommitGovernanceParams"
            ).withArgs([
                temporaryParams.gatewayVault,
                temporaryParams.protocolGovernance
            ]);
        });

        describe("when called by not admin", () => {
            it("reverts", async () => {
                temporaryProtocol = await deployProtocolGovernance();
                temporaryParams = {
                    gatewayVault: ethers.constants.AddressZero,
                    protocolGovernance: temporaryProtocol.address
                };
                await contract.setPendingGovernanceParams(temporaryParams);
                await expect(
                    contract.connect(stranger).commitGovernanceParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when pendingParamsTimestamp has not been set", () => {
            it("reverts", async () => {
                temporaryProtocol = await deployProtocolGovernance();
                temporaryParams = {
                    gatewayVault: ethers.constants.AddressZero,
                    protocolGovernance: temporaryProtocol.address
                };
                await expect(
                    contract.commitGovernanceParams()
                ).to.be.revertedWith(Exceptions.NULL);
            });
        }); 

        describe("when governanceDelay has not passed", () => {
            describe("commit called immediately", () => {
                it("reverts", async () => {
                    timestamp += 10**6;
                    await sleepTo(timestamp);
                    let newGovernanceParams = {
                        maxTokensPerVault: 9,
                        governanceDelay: timeout,
                        strategyPerformanceFee: 10,
                        protocolPerformanceFee: 11,
                        protocolExitFee: 12,
                        protocolTreasury: ethers.constants.AddressZero,
                        gatewayVaultManager: ethers.constants.AddressZero,
                    };
                    temporaryProtocol = await deployProtocolGovernance({
                        constructorArgs: {
                            admin: await deployer.getAddress(),
                            params: newGovernanceParams
                        },
                        adminSigner: deployer
                    });
                    temporaryParams = {
                        gatewayVault: ethers.constants.AddressZero,
                        protocolGovernance: temporaryProtocol.address
                    };
                    await contract.setPendingGovernanceParams(temporaryParams);
                    await expect(
                        contract.commitGovernanceParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
            
            describe("when governance delay has almost passed", () => {
                it("reverts", async () => {
                    let longTimeout = 10**3;
                    let newGovernanceParams = {
                        maxTokensPerVault: 9,
                        governanceDelay: longTimeout,
                        strategyPerformanceFee: 10,
                        protocolPerformanceFee: 11,
                        protocolExitFee: 12,
                        protocolTreasury: ethers.constants.AddressZero,
                        gatewayVaultManager: ethers.constants.AddressZero,
                    };
                    temporaryProtocol = await deployProtocolGovernance({
                        constructorArgs: {
                            admin: await deployer.getAddress(),
                            params: newGovernanceParams
                        },
                        adminSigner: deployer
                    });
                    temporaryParams = {
                        gatewayVault: ethers.constants.AddressZero,
                        protocolGovernance: temporaryProtocol.address
                    };

                    timestamp += 10**6;
                    await sleepTo(timestamp);
                    await contract.setPendingGovernanceParams(temporaryParams);
                    sleep(2 * longTimeout);
                    await contract.commitGovernanceParams();
                    
                    temporaryProtocol = await deployProtocolGovernance();
                    temporaryParams = {
                        gatewayVault: ethers.constants.AddressZero,
                        protocolGovernance: temporaryProtocol.address
                    };

                    timestamp += 10**6;
                    await sleepTo(timestamp);
                    await contract.setPendingGovernanceParams(temporaryParams);
                    sleep(longTimeout - timeEps);

                    await expect(
                        contract.commitGovernanceParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });
    });
});

