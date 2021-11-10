import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import { before } from "mocha";
import Exceptions from "./library/Exceptions";
import { now, sleep, sleepTo, toObject } from "./library/Helpers";
import { deployLpIssuerGovernance } from "./library/Deployments";
import {
    LpIssuerGovernance,
    ProtocolGovernance,
    ProtocolGovernance_Params,
    LpIssuerGovernance_constructorArgs,
    ProtocolGovernance_constructorArgs,
} from "./library/Types";

/**
 * TODO: Define some sort of default params for a series of tests
 * and then do smth like `{...defaultParams, maxTokensPerVault: 12}`
 */
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
        [deployer, stranger, protocolTreasury] = await ethers.getSigners();
        timeout = 5;
        timeEps = 2;
        timestamp = now() + 10 ** 2;

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            return await deployLpIssuerGovernance({
                constructorArgs: constructorArgs,
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

    describe("strategyTreasury", () => {
        it("treasury == 0x0", async () => {
            let nft = Math.random() * 2 ** 52;
            expect(await contract.strategyTreasury(nft)).to.be.equal(
                ethers.constants.AddressZero
            );
        });
    });

    describe("setStrategyParams", () => {
        it("sets strategy params and emits SetStrategyParams event", async () => {
            let nft = Math.random() * 2 ** 52;
            let tokenLimit = Math.random() * 2 ** 52;
            await expect(
                await contract.setDelayedStrategyParams(nft, {
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
});