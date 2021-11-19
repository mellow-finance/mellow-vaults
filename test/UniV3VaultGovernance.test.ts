import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { Signer } from "ethers";
import {
    VaultGovernance,
    ProtocolGovernance,
    VaultRegistry,
} from "./library/Types";
import { deploySubVaultSystem } from "./library/Deployments";
import { sleep, toObject } from "./library/Helpers";

describe("UniV3VaultGovernance", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let treasury: Signer;
    let anotherTreasury: Signer;
    let anotherPositionManager: Signer;
    let UniV3VaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let nftUniV3: number;
    let deployment: Function;
    let namedAccounts: any;
    let vaultRegistry: VaultRegistry;

    before(async () => {
        [deployer, admin, treasury, anotherTreasury, anotherPositionManager] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({
                protocolGovernance,
                UniV3VaultGovernance,
                nftUniV3,
                vaultRegistry,
            } = await deploySubVaultSystem({
                tokensCount: tokensCount,
                adminSigner: admin,
                treasury: await treasury.getAddress(),
                vaultOwner: await deployer.getAddress(),
            }));
        });
        namedAccounts = await getNamedAccounts();
    });

    beforeEach(async () => {
        await deployment();
    });

    describe("constructor", () => {
        it("create UniV3VaultGovernance", async () => {
            expect(
                await deployer.provider?.getCode(UniV3VaultGovernance.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("delayedStrategyParams", () => {
        it("returns correct params", async () => {
            expect(
                await UniV3VaultGovernance.delayedStrategyParams(nftUniV3)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty struct", async () => {
                expect(
                    await UniV3VaultGovernance.delayedStrategyParams(
                        nftUniV3 + 42
                    )
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });
    });

    describe("delayedProtocolParams", () => {
        it("returns correct params", async () => {
            expect(
                toObject(await UniV3VaultGovernance.delayedProtocolParams())
            ).to.be.deep.equal({
                positionManager: namedAccounts.uniswapV3PositionManager,
            });
        });

        describe("when delayedProtocolParams is empty", () => {
            it("returns zero address", async () => {
                let factory = await ethers.getContractFactory(
                    "UniV3VaultGovernanceTest"
                );
                let contract = await factory.deploy(
                    {
                        protocolGovernance: protocolGovernance.address,
                        registry: vaultRegistry.address,
                    },
                    { positionManager: namedAccounts.uniswapV3PositionManager }
                );
                expect(
                    toObject(await contract.delayedProtocolParams())
                ).to.be.deep.equal({
                    positionManager: ethers.constants.AddressZero,
                });
            });
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        it("returns params", async () => {
            const address = await treasury.getAddress();
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftUniV3, {
                strategyTreasury: address,
            });

            expect(
                await UniV3VaultGovernance.stagedDelayedStrategyParams(nftUniV3)
            ).to.be.deep.equal([address]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty struct", async () => {
                expect(
                    await UniV3VaultGovernance.stagedDelayedStrategyParams(
                        nftUniV3 + 42
                    )
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });
    });

    describe("stageDelayedStrategyParams", () => {
        it("stages DelayedStrategyParams", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftUniV3, [
                await anotherTreasury.getAddress(),
            ]);
            expect(
                await UniV3VaultGovernance.connect(
                    admin
                ).stagedDelayedStrategyParams(nftUniV3)
            ).to.be.deep.equal([await anotherTreasury.getAddress()]);
        });

        it("emits StageDelayedStrategyParams event", async () => {
            await expect(
                UniV3VaultGovernance.connect(admin).stageDelayedStrategyParams(
                    nftUniV3,
                    [await anotherTreasury.getAddress()]
                )
            ).to.emit(UniV3VaultGovernance, "StageDelayedStrategyParams");
        });
    });

    describe("strategyTreasury", () => {
        it("returns correct strategy treasury", async () => {
            expect(
                await UniV3VaultGovernance.strategyTreasury(nftUniV3)
            ).to.be.equal(await treasury.getAddress());
        });
    });

    describe("commitDelayedStrategyParams", () => {
        it("commits delayed strategy params", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftUniV3, [
                await anotherTreasury.getAddress(),
            ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await UniV3VaultGovernance.connect(
                admin
            ).commitDelayedStrategyParams(nftUniV3);
            expect(
                await UniV3VaultGovernance.strategyTreasury(nftUniV3)
            ).to.be.equal(await anotherTreasury.getAddress());
        });

        it("emits CommitDelayedStrategyParams event", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftUniV3, [
                await anotherTreasury.getAddress(),
            ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                UniV3VaultGovernance.connect(admin).commitDelayedStrategyParams(
                    nftUniV3
                )
            ).to.emit(UniV3VaultGovernance, "CommitDelayedStrategyParams");
        });
    });

    describe("stagedDelayedProtocolParams", () => {
        describe("when nothing is staged", async () => {
            it("returns an empty struct", async () => {
                expect(
                    await UniV3VaultGovernance.stagedDelayedProtocolParams()
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });

        it("returns staged params", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedProtocolParams([
                await anotherPositionManager.getAddress(),
            ]);
            expect(
                await UniV3VaultGovernance.connect(
                    admin
                ).stagedDelayedProtocolParams()
            ).to.be.deep.equal([await anotherPositionManager.getAddress()]);
        });
    });

    describe("stageDelayedProtocolParams", () => {
        it("stages DelayedProtocolParams", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedProtocolParams([
                await anotherPositionManager.getAddress(),
            ]);
            expect(
                await UniV3VaultGovernance.connect(
                    admin
                ).stagedDelayedProtocolParams()
            ).to.be.deep.equal([await anotherPositionManager.getAddress()]);
        });

        it("emits StageDelayedProtocolParams event", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedProtocolParams([
                await anotherPositionManager.getAddress(),
            ]);
            await expect(
                UniV3VaultGovernance.connect(admin).stageDelayedProtocolParams([
                    await anotherPositionManager.getAddress(),
                ])
            ).to.emit(UniV3VaultGovernance, "StageDelayedProtocolParams");
        });
    });

    describe("commitDelayedProtocolParams", () => {
        it("commits delayed protocol params", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedProtocolParams([
                await anotherPositionManager.getAddress(),
            ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await UniV3VaultGovernance.connect(
                admin
            ).commitDelayedProtocolParams();
            expect(
                await UniV3VaultGovernance.delayedProtocolParams()
            ).to.deep.equal([await anotherPositionManager.getAddress()]);
        });

        it("emits CommitDelayedProtocolParams event", async () => {
            await UniV3VaultGovernance.connect(
                admin
            ).stageDelayedProtocolParams([
                await anotherPositionManager.getAddress(),
            ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                UniV3VaultGovernance.connect(
                    admin
                ).commitDelayedProtocolParams()
            ).to.emit(UniV3VaultGovernance, "CommitDelayedProtocolParams");
        });
    });
});
