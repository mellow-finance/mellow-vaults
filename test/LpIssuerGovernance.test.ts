import { expect } from "chai";
import { 
    ethers,
    deployments
} from "hardhat";
import {
    BigNumber,
    Signer
} from "ethers";
import { before } from "mocha";
import Exceptions from "./library/Exceptions";
import {
    now,
    sleep, 
    sleepTo,
    toObject
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
    let params: ProtocolGovernance_Params;
    let timestamp: number;
    let timeout: number;
    let timeEps: number;
    let deploymentFixture: Function;
    let deployer: Signer;
    let stranger: Signer;
    let gatewayVault: Signer;
    let protocolTreasury: Signer;
    let gatewayVaultManager: Signer;

    before(async () => {
        [deployer, stranger, gatewayVault, protocolTreasury, gatewayVaultManager] = await ethers.getSigners();
        timeout = 5;
        timeEps = 2;
        timestamp = now() + 10**2;

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            
            emptyParams = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: ethers.constants.AddressZero
            };

            protocolConstructorArgs = {
                admin: await deployer.getAddress()
            }

            params = {
                maxTokensPerVault: BigNumber.from(2),
                governanceDelay: BigNumber.from(1),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(1 * 10 ** 9),
                protocolTreasury: await gatewayVault.getAddress(),
                gatewayVaultManager: await protocolTreasury.getAddress()
            }

            protocol = await deployProtocolGovernance({
                constructorArgs: protocolConstructorArgs,
                initializerArgs: {params},
                adminSigner: deployer
            });

            constructorArgs = {
                gatewayVault: await gatewayVault.getAddress(),
                protocolGovernance: protocol.address
            };
            return await deployLpIssuerGovernance({constructorArgs});
        });
    });

    beforeEach(async () => {
        contract = await deploymentFixture();
    });

    describe("constructor", () => {
        describe("governanceParams", () => {
            it("is set by constructor", async () => {
                expect(
                    toObject(await contract.governanceParams())
                ).to.deep.equal(constructorArgs);
            });
        });
        
        describe("pendingGovernanceParams", () => {
            it("is empty", async () => {
                expect(
                    toObject(await contract.pendingGovernanceParams())
                ).to.deep.equal(emptyParams);
            });
        });
        
        describe("pendingGovernanceParamsTimestamp", () => {
            it("is zero", async () => {
                expect(
                    await contract.pendingGovernanceParamsTimestamp()
                ).to.be.equal(BigNumber.from(0));
            }); 
        }); 
    });

    describe("setPendingGovernanceParams", () => {
        it("sets pending params", async () => {
            temporaryProtocol = await deployProtocolGovernance();
            temporaryParams = {
                gatewayVault: await gatewayVault.getAddress(),
                protocolGovernance: await protocolTreasury.getAddress(),
            };

            await contract.setPendingGovernanceParams(temporaryParams);
            expect(
                toObject(await contract.pendingGovernanceParams())
            ).to.deep.equal(temporaryParams);
        });

        it("sets params timestamp and emits SetPendingGovernanceParams", async () => {
            await sleepTo(timestamp);
            params = {
                maxTokensPerVault: BigNumber.from(2),
                governanceDelay: BigNumber.from(timeout),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(1 * 10 ** 9),
                protocolTreasury: await gatewayVault.getAddress(),
                gatewayVaultManager: await protocolTreasury.getAddress()
            }
            temporaryProtocol = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await deployer.getAddress()
                },
                initializerArgs: {params},
                adminSigner: deployer
            });
            temporaryParams = {
                gatewayVault: await gatewayVault.getAddress(),
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
            expect(
                Math.abs(await contract.pendingGovernanceParamsTimestamp() - (timestamp + timeout))
            ).to.be.lessThanOrEqual(timeEps);
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
        it("commits params and emits CommitGovernanceParams event", async () => {
            timestamp += 10**6;
            await sleepTo(timestamp);
            params = {
                maxTokensPerVault: BigNumber.from(5),
                governanceDelay: BigNumber.from(timeout),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(1 * 10 ** 9),
                protocolTreasury: await gatewayVault.getAddress(),
                gatewayVaultManager: await protocolTreasury.getAddress()
            }
            temporaryProtocol = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await deployer.getAddress(),
                },
                initializerArgs: {params},
                adminSigner: deployer
            });
            temporaryParams = {
                gatewayVault: await gatewayVault.getAddress(),
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

            expect(
                toObject(await contract.governanceParams())
            ).to.deep.equal(temporaryParams);
        });

        describe("when called by not admin", () => {
            it("reverts", async () => {
                temporaryProtocol = await deployProtocolGovernance();
                temporaryParams = {
                    gatewayVault: await gatewayVault.getAddress(),
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
                    gatewayVault: await gatewayVault.getAddress(),
                    protocolGovernance: temporaryProtocol.address
                };
                await expect(
                    contract.commitGovernanceParams()
                ).to.be.revertedWith(Exceptions.NULL);
            });
        }); 

        describe("when governanceDelay has not passed", () => {
            describe("when commit called immediately", () => {
                it("reverts", async () => {
                    timestamp += 10**6;
                    await sleepTo(timestamp);
                    params = {
                        maxTokensPerVault: BigNumber.from(5),
                        governanceDelay: BigNumber.from(timeout),
                        strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                        protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                        protocolExitFee: BigNumber.from(1 * 10 ** 9),
                        protocolTreasury: await gatewayVault.getAddress(),
                        gatewayVaultManager: await protocolTreasury.getAddress()
                    }
                    temporaryProtocol = await deployProtocolGovernance({
                        constructorArgs: {
                            admin: await deployer.getAddress(),
                        },
                        initializerArgs: {params}, 
                        adminSigner: deployer
                    });
                    temporaryParams = {
                        gatewayVault: await gatewayVault.getAddress(),
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
                    params = {
                        maxTokensPerVault: BigNumber.from(2),
                        governanceDelay: BigNumber.from(longTimeout),
                        strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                        protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                        protocolExitFee: BigNumber.from(1 * 10 ** 9),
                        protocolTreasury: await gatewayVault.getAddress(),
                        gatewayVaultManager: await protocolTreasury.getAddress()
                    }
                    temporaryProtocol = await deployProtocolGovernance({
                        constructorArgs: {
                            admin: await deployer.getAddress(),
                        },
                        initializerArgs: {params},
                        adminSigner: deployer
                    });
                    temporaryParams = {
                        gatewayVault: await gatewayVault.getAddress(),
                        protocolGovernance: temporaryProtocol.address
                    };

                    timestamp += 10**6;
                    await sleepTo(timestamp);
                    await contract.setPendingGovernanceParams(temporaryParams);
                    sleep(2 * longTimeout);
                    await contract.commitGovernanceParams();
                    
                    temporaryProtocol = await deployProtocolGovernance();
                    temporaryParams = {
                        gatewayVault: await gatewayVault.getAddress(),
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

