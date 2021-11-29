import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import { before } from "mocha";
import { toObject } from "./library/Helpers";
import { deployLpIssuerGovernance } from "./library/Deployments";
import {
    LpIssuerGovernance,
    LpIssuerGovernance_constructor,
} from "./library/Types";

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
});
