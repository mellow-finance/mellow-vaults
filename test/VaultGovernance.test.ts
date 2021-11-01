import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import { before } from "mocha";
import Exceptions from "./library/Exceptions";
import { now, sleep, sleepTo, toObject } from "./library/Helpers";
import {
    deployProtocolGovernance,
    deployTestVaultGovernance,
    deployVaultRegistry
} from "./library/Deployments";
import {
    ProtocolGovernance,
    TestVaultGovernance,
    VaultGovernance_constructorArgs,
    VaultGovernance_InternalParams,
    VaultRegistry
} from "./library/Types";
import { time } from "console";

describe("TestVaultGovernance", () => {
    let deploymentFixture: Function;
    let deployer: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let contract: TestVaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vaultRegistry: VaultRegistry;
    let initialParams: VaultGovernance_InternalParams;
    let emptyParams: VaultGovernance_InternalParams;
    let timestamp: number;
    let timeshift: number;
    let timeEps: number;

    before(async () => {
        timestamp = now();
        timeshift = 10 ** 4;
        timeEps = 2;

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            [deployer, stranger, treasury] = await ethers.getSigners();

            protocolGovernance = await deployProtocolGovernance({
                adminSigner: deployer
            });
            vaultRegistry = await deployVaultRegistry({
                name: "name",
                symbol: "sym",
                permissionless: true,
                protocolGovernance: protocolGovernance
            });

            initialParams = {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address
            };

            emptyParams = {
                protocolGovernance: ethers.constants.AddressZero,
                registry: ethers.constants.AddressZero
            };

            return await deployTestVaultGovernance({
                constructorArgs: {
                    params: initialParams
                },
                adminSigner: deployer,
                treasury: await treasury.getAddress()
            });
        });
    });

    beforeEach(async () => {
        contract = await deploymentFixture();
    });

    describe("constructor", () => {
        it("internal params timestamp == 0", async () => {
            expect(
                await contract.internalParamsTimestamp()
            ).to.be.equal(BigNumber.from(0));
        });

        it("sets initial internal params", async () => {
            expect(
                toObject(await contract.internalParams())
            ).to.deep.equal(initialParams);
        });

        it("has no staged internal params", async () => {
            expect(
                toObject(await contract.stagedInternalParams())
            ).to.deep.equal(emptyParams);
        });

        it("strategy treasury == 0x0", async () => {
            for (let i: number = 0; i < 10; ++i) {
                expect(
                    await contract.strategyTreasury(Math.random() * (2 ** 52))
                ).to.be.equal(BigNumber.from(0));
            }

            expect(
                await contract.strategyTreasury(0)
            ).to.be.equal(
                ethers.constants.AddressZero
            );
        });

        it("delayed protocol params timestamp == 0", async () => {
            expect(
                await contract.delayedProtocolParamsTimestamp()
            ).to.be.equal(BigNumber.from(0));
        });

        it("has zero delayed strategy params timestamps", async () => {
            expect(
                await contract.delayedStrategyParamsTimestamp(0)
            ).to.be.equal(BigNumber.from(0));

            for (let i: number = 0; i < 100; ++i) {
                expect(
                    await contract.delayedStrategyParamsTimestamp(Math.random() * (2 ** 52))
                ).to.be.equal(BigNumber.from(0));
            }
        });
    });

    describe("stageInternalParams", () => {
        describe("when called by not admin", () => {
            it("reverts", async () => {
                await expect(
                    contract.connect(stranger).stageInternalParams(initialParams)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        it("sets internal params timestamp", async () => {
            timestamp += timeshift
            sleepTo(timestamp);
            await contract.stageInternalParams(initialParams);
            expect(
                Math.abs(await contract.internalParamsTimestamp() - timestamp)
            ).lessThanOrEqual(timeEps);
        });

        it("sets params and emits StagedInternalParams", async () => {
            // timestamp += timeshift
            // sleepTo(timestamp);
            // await expect(
            //     await contract.stageInternalParams(initialParams.params)
            // ).to.emit(contract, "StagedInternalParams").withArgs(
            //     await deployer.getAddress(),
            //     await deployer.getAddress(),
            //     [
            //         initialParams.params.protocolGovernance,
            //         initialParams.params.registry
            //     ],
            //     timestamp + 1
            // );

            let customParams: VaultGovernance_InternalParams;

            let newProtocolGovernance = await deployProtocolGovernance({
                adminSigner: deployer
            });
            let newVaultRegistry = await deployVaultRegistry({
                name: "",
                symbol: "",
                permissionless: false,
                protocolGovernance: newProtocolGovernance
            });

            customParams = {
                protocolGovernance: newProtocolGovernance.address,
                registry: newVaultRegistry.address
            }

            await expect(
                await contract.stageInternalParams(customParams)
            ).to.emit(contract, "StagedInternalParams");

            expect(
                toObject(await contract.stagedInternalParams())
            ).to.deep.equal(customParams);
        });
    });

    describe("commitInternalParams", () => {
        describe("when called by not admin", () => {
            it("reverts", async () => {
                await contract.stageInternalParams(initialParams);

                await expect(
                    contract.connect(stranger).commitInternalParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when internal params timestamp == 0", () => {
            it("reverts", async () => {
                await expect(
                    contract.commitInternalParams()
                ).to.be.revertedWith(Exceptions.NULL);
            });
        });

        describe("when governance delay has not passed or has almost passed", () => {
            it("reverts", async () => {
                let customParams: VaultGovernance_InternalParams;
                
                let newProtocolGovernance = await deployProtocolGovernance({
                    constructorArgs: {
                        admin: await deployer.getAddress()
                    },
                    adminSigner: deployer
                });
                
                let newVaultRegistry = await deployVaultRegistry({
                    name: "",
                    symbol: "",
                    permissionless: false,
                    protocolGovernance: newProtocolGovernance
                });
                
                await newProtocolGovernance.setPendingParams({
                        maxTokensPerVault: BigNumber.from(2),
                        governanceDelay: BigNumber.from(100),
                        protocolPerformanceFee: BigNumber.from(10 ** 9),
                        strategyPerformanceFee: BigNumber.from(10 ** 9),
                        protocolExitFee: BigNumber.from(10 ** 9),
                        protocolTreasury: await treasury.getAddress(),
                        vaultRegistry: newVaultRegistry.address
                });
                
                await newProtocolGovernance.commitParams();

                customParams = {
                    protocolGovernance: newProtocolGovernance.address,
                    registry: newVaultRegistry.address
                }
                
                timestamp += timeshift;
                sleepTo(timestamp);

                await contract.stageInternalParams(customParams);

                await contract.commitInternalParams();

                await contract.stageInternalParams(initialParams);
                
                await expect(
                    contract.commitInternalParams()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);

                sleep(95);
                await expect(
                    contract.commitInternalParams()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });

        it("sets new params, deletes internal params timestamp, emits CommitedInternalParams", async () => {
            let customParams: VaultGovernance_InternalParams;
                
            let newProtocolGovernance = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await deployer.getAddress()
                },
                adminSigner: deployer
            });
            
            let newVaultRegistry = await deployVaultRegistry({
                name: "NAME",
                symbol: "SYM",
                permissionless: false,
                protocolGovernance: newProtocolGovernance
            });

            customParams = {
                protocolGovernance: newProtocolGovernance.address,
                registry: newVaultRegistry.address
            }
            
            await contract.stageInternalParams(customParams);
            await expect(
                contract.commitInternalParams()
            ).to.emit(contract, "CommitedInternalParams");

            expect(
                await contract.internalParamsTimestamp()
            ).to.be.equal(BigNumber.from(0));

            expect(
                toObject(await contract.internalParams())
            ).to.deep.equal(
                customParams
            );
        });
    });
});