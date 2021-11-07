import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
} from "./library/Types";
import { deployERC20VaultSystem } from "./library/Deployments";
import { sleep } from "./library/Helpers";

describe("ERC20VaultGovernance", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let anotherTreasury: Signer;
    let vaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: Vault;
    let nft: number;
    let tokens: ERC20[];
    let deployment: Function;

    before(async () => {
        [deployer, admin, stranger, treasury, anotherTreasury] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({ protocolGovernance, vaultGovernance, tokens, nft } =
                await deployERC20VaultSystem({
                    tokensCount: tokensCount,
                    adminSigner: admin,
                    treasury: await treasury.getAddress(),
                    vaultOwner: await deployer.getAddress(),
                }));
        });
    });

    beforeEach(async () => {
        await deployment();
    });

    describe("constructor", () => {
        it("passes", async () => {
            expect(
                await deployer.provider?.getCode(vaultGovernance.address)
            ).not.to.be.equal(0);
        });
    });

    describe("delayedStrategyParams", () => {
        it("returns correct params", async () => {
            expect(
                await vaultGovernance.delayedStrategyParams(nft)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        it("returns params", async () => {
            expect(
                await vaultGovernance.stagedDelayedStrategyParams(nft)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });
    });

    describe("stageDelayedStrategyParams", () => {
        it("passes", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedStrategyParams(nft, [
                    await anotherTreasury.getAddress(),
                ]);
            expect(
                await vaultGovernance
                    .connect(admin)
                    .stagedDelayedStrategyParams(nft)
            ).to.be.deep.equal([await anotherTreasury.getAddress()]);
        });

        it("emits", async () => {
            await expect(
                vaultGovernance
                    .connect(admin)
                    .stageDelayedStrategyParams(nft, [
                        await anotherTreasury.getAddress(),
                    ])
            ).to.emit(vaultGovernance, "StageDelayedStrategyParams");
        });
    });

    describe("strategyTreasury", () => {
        it("returns correct strategy treasury", async () => {
            expect(await vaultGovernance.strategyTreasury(nft)).to.be.equal(
                await treasury.getAddress()
            );
        });
    });

    describe("commitDelayedStrategyParams", () => {
        it("commits delayed strategy params", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedStrategyParams(nft, [
                    await anotherTreasury.getAddress(),
                ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await vaultGovernance
                .connect(admin)
                .commitDelayedStrategyParams(nft);
            expect(await vaultGovernance.strategyTreasury(nft)).to.be.equal(
                await anotherTreasury.getAddress()
            );
        });

        it("emits", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedStrategyParams(nft, [
                    await anotherTreasury.getAddress(),
                ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                vaultGovernance.connect(admin).commitDelayedStrategyParams(nft)
            ).to.emit(vaultGovernance, "CommitDelayedStrategyParams");
        });
    });
});
