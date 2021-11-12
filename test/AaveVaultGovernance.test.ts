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
    let AaveVaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: Vault;
    let nftAave: number;
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
            ({ protocolGovernance, AaveVaultGovernance, tokens, nftAave } =
                await deploySubVaultSystem({
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
        it("creates AaveVaultGovernance", async () => {
            expect(
                await deployer.provider?.getCode(AaveVaultGovernance.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("delayedStrategyParams", () => {
        it("returns correct params", async () => {
            expect(
                await AaveVaultGovernance.delayedStrategyParams(nftAave)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        it("returns params", async () => {
            expect(
                await AaveVaultGovernance.stagedDelayedStrategyParams(nftAave)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });
    });

    describe("stageDelayedStrategyParams", () => {
        it("stages DelayedStrategyParams", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedStrategyParams(
                nftAave,
                [await anotherTreasury.getAddress()]
            );
            expect(
                await AaveVaultGovernance.connect(
                    admin
                ).stagedDelayedStrategyParams(nftAave)
            ).to.be.deep.equal([await anotherTreasury.getAddress()]);
        });

        it("emits StageDelayedStrategyParams event", async () => {
            await expect(
                AaveVaultGovernance.connect(admin).stageDelayedStrategyParams(
                    nftAave,
                    [await anotherTreasury.getAddress()]
                )
            ).to.emit(AaveVaultGovernance, "StageDelayedStrategyParams");
        });
    });

    describe("strategyTreasury", () => {
        it("returns correct strategy treasury", async () => {
            expect(
                await AaveVaultGovernance.strategyTreasury(nftAave)
            ).to.be.equal(await treasury.getAddress());
        });
    });

    describe("commitDelayedStrategyParams", () => {
        it("commits delayed strategy params", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedStrategyParams(
                nftAave,
                [await anotherTreasury.getAddress()]
            );
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await AaveVaultGovernance.connect(
                admin
            ).commitDelayedStrategyParams(nftAave);
            expect(
                await AaveVaultGovernance.strategyTreasury(nftAave)
            ).to.be.equal(await anotherTreasury.getAddress());
        });

        it("emits CommitDelayedStrategyParams event", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedStrategyParams(
                nftAave,
                [await anotherTreasury.getAddress()]
            );
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                AaveVaultGovernance.connect(admin).commitDelayedStrategyParams(
                    nftAave
                )
            ).to.emit(AaveVaultGovernance, "CommitDelayedStrategyParams");
        });
    });

    describe("stagedDelayedProtocolParams", () => {
        describe("when nothing is staged", async () => {
            it("returns an empty struct", async () => {
                expect(
                    await AaveVaultGovernance.stagedDelayedProtocolParams()
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });

        it("returns staged params", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedProtocolParams(
                [await anotherAaveLendingPool.getAddress()]
            );
            expect(
                await AaveVaultGovernance.connect(
                    admin
                ).stagedDelayedProtocolParams()
            ).to.be.deep.equal([await anotherAaveLendingPool.getAddress()]);
        });
    });

    describe("stageDelayedProtocolParams", () => {
        it("stages DelayedProtocolParams", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedProtocolParams(
                [await anotherAaveLendingPool.getAddress()]
            );
            expect(
                await AaveVaultGovernance.connect(
                    admin
                ).stagedDelayedProtocolParams()
            ).to.be.deep.equal([await anotherAaveLendingPool.getAddress()]);
        });

        it("emits StageDelayedProtocolParams event", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedProtocolParams(
                [await anotherAaveLendingPool.getAddress()]
            );
            await expect(
                AaveVaultGovernance.connect(admin).stageDelayedProtocolParams([
                    await anotherAaveLendingPool.getAddress(),
                ])
            ).to.emit(AaveVaultGovernance, "StageDelayedProtocolParams");
        });
    });

    describe("commitDelayedProtocolParams", () => {
        it("commits delayed protocol params", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedProtocolParams(
                [await anotherAaveLendingPool.getAddress()]
            );
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await AaveVaultGovernance.connect(
                admin
            ).commitDelayedProtocolParams();
            expect(
                await AaveVaultGovernance.delayedProtocolParams()
            ).to.deep.equal([await anotherAaveLendingPool.getAddress()]);
        });

        it("emits CommitDelayedProtocolParams event", async () => {
            await AaveVaultGovernance.connect(admin).stageDelayedProtocolParams(
                [await anotherAaveLendingPool.getAddress()]
            );
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                AaveVaultGovernance.connect(admin).commitDelayedProtocolParams()
            ).to.emit(AaveVaultGovernance, "CommitDelayedProtocolParams");
        });
    });
});
