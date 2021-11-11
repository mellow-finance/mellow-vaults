import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
} from "./library/Types";
import { deploySubVaultSystem } from "./library/Deployments";
import { sleep } from "./library/Helpers";

describe("AaveVaultGovernance", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let anotherTreasury: Signer;
    let anotherAaveLendingPool: Signer;
    let vaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: Vault;
    let nft: number;
    let tokens: ERC20[];
    let deployment: Function;

    before(async () => {
        [
            deployer,
            admin,
            stranger,
            treasury,
            anotherTreasury,
            anotherAaveLendingPool,
        ] = await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({ protocolGovernance, vaultGovernance, tokens, nft } =
                await deploySubVaultSystem({
                    tokensCount: tokensCount,
                    adminSigner: admin,
                    treasury: await treasury.getAddress(),
                    vaultOwner: await deployer.getAddress(),
                    vaultType: "AaveVault",
                }));
        });
    });

    beforeEach(async () => {
        await deployment();
    });

    describe("constructor", () => {
        it("creates AaveVaultGovernance", async () => {
            expect(
                await deployer.provider?.getCode(vaultGovernance.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("delayedStrategyParams", () => {
        it("returns correct params", async () => {
            expect(
                await vaultGovernance.delayedStrategyParams(nft)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty struct", async () => {
                expect(
                    await vaultGovernance.delayedStrategyParams(nft + 1)
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        it("returns params", async () => {
            expect(
                await vaultGovernance.stagedDelayedStrategyParams(nft)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty struct", async () => {
                expect(
                    await vaultGovernance.stagedDelayedStrategyParams(nft + 1)
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });
    });

    describe("stageDelayedStrategyParams", () => {
        it("stages DelayedStrategyParams", async () => {
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

        it("emits StageDelayedStrategyParams event", async () => {
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

        it("emits CommitDelayedStrategyParams event", async () => {
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

    describe("stagedDelayedProtocolParams", () => {
        describe("when nothing is staged", async () => {
            it("returns an empty struct", async () => {
                expect(
                    await vaultGovernance.stagedDelayedProtocolParams()
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });

        it("returns staged params", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedProtocolParams([
                    await anotherAaveLendingPool.getAddress(),
                ]);
            expect(
                await vaultGovernance
                    .connect(admin)
                    .stagedDelayedProtocolParams()
            ).to.be.deep.equal([await anotherAaveLendingPool.getAddress()]);
        });
    });

    describe("stageDelayedProtocolParams", () => {
        it("stages DelayedProtocolParams", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedProtocolParams([
                    await anotherAaveLendingPool.getAddress(),
                ]);
            expect(
                await vaultGovernance
                    .connect(admin)
                    .stagedDelayedProtocolParams()
            ).to.be.deep.equal([await anotherAaveLendingPool.getAddress()]);
        });

        it("emits StageDelayedProtocolParams event", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedProtocolParams([
                    await anotherAaveLendingPool.getAddress(),
                ]);
            await expect(
                vaultGovernance
                    .connect(admin)
                    .stageDelayedProtocolParams([
                        await anotherAaveLendingPool.getAddress(),
                    ])
            ).to.emit(vaultGovernance, "StageDelayedProtocolParams");
        });
    });

    describe("commitDelayedProtocolParams", () => {
        it("commits delayed protocol params", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedProtocolParams([
                    await anotherAaveLendingPool.getAddress(),
                ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await vaultGovernance.connect(admin).commitDelayedProtocolParams();
            expect(await vaultGovernance.delayedProtocolParams()).to.deep.equal(
                [await anotherAaveLendingPool.getAddress()]
            );
        });

        it("emits CommitDelayedProtocolParams event", async () => {
            await vaultGovernance
                .connect(admin)
                .stageDelayedProtocolParams([
                    await anotherAaveLendingPool.getAddress(),
                ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                vaultGovernance.connect(admin).commitDelayedProtocolParams()
            ).to.emit(vaultGovernance, "CommitDelayedProtocolParams");
        });
    });
});
