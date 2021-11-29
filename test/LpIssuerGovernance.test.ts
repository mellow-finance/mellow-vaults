import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber, Signer } from "ethers";
import { before } from "mocha";
import { randomAddress, sleep, toObject } from "./library/Helpers";
import { deployLpIssuerGovernance } from "./library/Deployments";
import {
    LpIssuerGovernance,
    LpIssuerGovernance_constructor,
} from "./library/Types";
import { DelayedStrategyParamsStruct } from "./types/ILpIssuerGovernance";

/**
 * TODO: Define some sort of default params for a series of tests
 * and then do smth like `{...defaultParams, maxTokensPerVault: 12}`
 */
describe("LpIssuerGovernance", () => {
    let contract: LpIssuerGovernance;
    let deploymentFixture: Function;
    let deployer: Signer;
    let protocolTreasury: Signer;

    before(async () => {
        [deployer, protocolTreasury] = await ethers.getSigners();

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            return await deployLpIssuerGovernance({
                adminSigner: deployer,
                treasury: await protocolTreasury.getAddress(),
            });
        });
    });

    beforeEach(async () => {
        let LpIssuerGovernanceSystem = await deploymentFixture();
        contract = LpIssuerGovernanceSystem.LpIssuerGovernance;
    });

    describe("constructor", () => {
        it("deploys", async () => {
            expect(contract.address).to.not.be.equal(
                ethers.constants.AddressZero
            );
        });
    });

    describe("setStrategyParams", () => {
        it("sets strategy params and emits SetStrategyParams event", async () => {
            let nft = Math.random() * 2 ** 52;
            let tokenLimit = Math.random() * 2 ** 52;
            await expect(
                await contract.setStrategyParams(nft, {
                    tokenLimitPerAddress: tokenLimit,
                })
            ).to.emit(contract, "SetStrategyParams");
        });
    });

    describe("strategyParams", () => {
        it("returns correct strategy params", async () => {
            let nft = Math.random() * 2 ** 52;
            let tokenLimit = Math.random() * 2 ** 52;
            await contract.setStrategyParams(nft, {
                tokenLimitPerAddress: tokenLimit,
            });
            expect(toObject(await contract.strategyParams(nft))).to.deep.equal({
                tokenLimitPerAddress: BigNumber.from(tokenLimit),
            });
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        const paramsToStage: DelayedStrategyParamsStruct = {
            strategyTreasury: randomAddress(),
            strategyPerformanceTreasury: randomAddress(),
            managementFee: BigNumber.from(1000),
            performanceFee: BigNumber.from(2000),
        };
        let nft: number;
        let deploy: Function;
        let admin: string;
        let deployer: string;

        before(async () => {
            const {
                weth,
                wbtc,
                admin: a,
                deployer: d,
            } = await getNamedAccounts();
            [admin, deployer] = [a, d];
            deploy = deployments.createFixture(async () => {
                const tokens = [weth, wbtc].map((t) => t.toLowerCase()).sort();
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: deployer, autoMine: true },
                    "deployVault",
                    tokens,
                    [],
                    deployer
                );
                const yearnNft = (
                    await deployments.read("VaultRegistry", "vaultsCount")
                ).toNumber();
                const coder = ethers.utils.defaultAbiCoder;
                await deployments.execute(
                    "LpIssuerGovernance",
                    { from: deployer, autoMine: true },
                    "deployVault",
                    tokens,
                    coder.encode(
                        ["uint256", "string", "string"],
                        [yearnNft, "Test token", "Test token"]
                    ),
                    deployer
                );
            });
        });

        beforeEach(async () => {
            await deploy();
            nft = (
                await deployments.read("VaultRegistry", "vaultsCount")
            ).toNumber();
        });

        it("returns delayed strategy params staged for commit", async () => {
            await deployments.execute(
                "LpIssuerGovernance",
                { from: admin, autoMine: true },
                "stageDelayedStrategyParams",
                nft,
                paramsToStage
            );

            const stagedParams = await deployments.read(
                "LpIssuerGovernance",
                "stagedDelayedStrategyParams",
                nft
            );
            expect(toObject(stagedParams)).to.eql(paramsToStage);
        });

        describe("when uninitialized", () => {
            it("returns zero struct", async () => {
                const expectedParams: DelayedStrategyParamsStruct = {
                    strategyTreasury: ethers.constants.AddressZero,
                    strategyPerformanceTreasury: ethers.constants.AddressZero,
                    managementFee: BigNumber.from(0),
                    performanceFee: BigNumber.from(0),
                };
                const stagedParams = await deployments.read(
                    "LpIssuerGovernance",
                    "stagedDelayedStrategyParams",
                    nft
                );
                expect(toObject(stagedParams)).to.eql(expectedParams);
            });
        });
    });

    describe("delayedStrategyParams", () => {
        const paramsToStage: DelayedStrategyParamsStruct = {
            strategyTreasury: randomAddress(),
            strategyPerformanceTreasury: randomAddress(),
            managementFee: BigNumber.from(1000),
            performanceFee: BigNumber.from(2000),
        };
        let nft: number;
        let deploy: Function;
        let admin: string;
        let deployer: string;

        before(async () => {
            const {
                weth,
                wbtc,
                admin: a,
                deployer: d,
            } = await getNamedAccounts();
            [admin, deployer] = [a, d];
            deploy = deployments.createFixture(async () => {
                const tokens = [weth, wbtc].map((t) => t.toLowerCase()).sort();
                await deployments.execute(
                    "YearnVaultGovernance",
                    { from: deployer, autoMine: true },
                    "deployVault",
                    tokens,
                    [],
                    deployer
                );
                const yearnNft = (
                    await deployments.read("VaultRegistry", "vaultsCount")
                ).toNumber();
                const coder = ethers.utils.defaultAbiCoder;
                await deployments.execute(
                    "LpIssuerGovernance",
                    { from: deployer, autoMine: true },
                    "deployVault",
                    tokens,
                    coder.encode(
                        ["uint256", "string", "string"],
                        [yearnNft, "Test token", "Test token"]
                    ),
                    deployer
                );
            });
        });

        beforeEach(async () => {
            await deploy();
            nft = (
                await deployments.read("VaultRegistry", "vaultsCount")
            ).toNumber();
        });

        it("returns delayed strategy params staged for commit", async () => {
            await deployments.execute(
                "LpIssuerGovernance",
                { from: admin, autoMine: true },
                "stageDelayedStrategyParams",
                nft,
                paramsToStage
            );

            const governanceDelay = await deployments.read(
                "ProtocolGovernance",
                "governanceDelay"
            );
            await sleep(governanceDelay);

            await deployments.execute(
                "LpIssuerGovernance",
                { from: admin, autoMine: true },
                "commitDelayedStrategyParams",
                nft
            );

            const params = await deployments.read(
                "LpIssuerGovernance",
                "delayedStrategyParams",
                nft
            );
            expect(toObject(params)).to.eql(paramsToStage);
        });

        describe("when uninitialized", () => {
            it("returns zero struct", async () => {
                const expectedParams: DelayedStrategyParamsStruct = {
                    strategyTreasury: ethers.constants.AddressZero,
                    strategyPerformanceTreasury: ethers.constants.AddressZero,
                    managementFee: BigNumber.from(0),
                    performanceFee: BigNumber.from(0),
                };
                const params = await deployments.read(
                    "LpIssuerGovernance",
                    "delayedStrategyParams",
                    nft
                );
                expect(toObject(params)).to.eql(expectedParams);
            });
        });
    });
});
