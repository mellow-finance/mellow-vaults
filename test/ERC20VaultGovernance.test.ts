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

describe("ERC20VaultGovernance", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let anotherTreasury: Signer;
    let ERC20VaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: Vault;
    let nftERC20: number;
    let tokens: ERC20[];
    let deployment: Function;

    before(async () => {
        [deployer, admin, stranger, treasury, anotherTreasury] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({ protocolGovernance, ERC20VaultGovernance, tokens, nftERC20 } =
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
        it("creates ERC20VaultGovernance", async () => {
            expect(
                await deployer.provider?.getCode(ERC20VaultGovernance.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("delayedStrategyParams", () => {
        it("returns correct params", async () => {
            expect(
                await ERC20VaultGovernance.delayedStrategyParams(nftERC20)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty params", async () => {
                expect(
                    await vaultGovernance.delayedStrategyParams(nft + 1)
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        it("returns params", async () => {
            expect(
                await ERC20VaultGovernance.stagedDelayedStrategyParams(nftERC20)
            ).to.be.deep.equal([await treasury.getAddress()]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty params", async () => {
                expect(
                    await vaultGovernance.stagedDelayedStrategyParams(nft + 1)
                ).to.be.deep.equal([ethers.constants.AddressZero]);
            });
        });
    });

    describe("stageDelayedStrategyParams", () => {
        it("stages DelayedStrategyParams for commit", async () => {
            await ERC20VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftERC20, [
                await anotherTreasury.getAddress(),
            ]);
            expect(
                await ERC20VaultGovernance.connect(
                    admin
                ).stagedDelayedStrategyParams(nftERC20)
            ).to.be.deep.equal([await anotherTreasury.getAddress()]);
        });

        it("emits", async () => {
            await expect(
                ERC20VaultGovernance.connect(admin).stageDelayedStrategyParams(
                    nftERC20,
                    [await anotherTreasury.getAddress()]
                )
            ).to.emit(ERC20VaultGovernance, "StageDelayedStrategyParams");
        });
    });

    describe("strategyTreasury", () => {
        it("returns correct strategy treasury", async () => {
            expect(
                await ERC20VaultGovernance.strategyTreasury(nftERC20)
            ).to.be.equal(await treasury.getAddress());
        });
    });

    describe("commitDelayedStrategyParams", () => {
        it("commits delayed strategy params", async () => {
            await ERC20VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftERC20, [
                await anotherTreasury.getAddress(),
            ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await ERC20VaultGovernance.connect(
                admin
            ).commitDelayedStrategyParams(nftERC20);
            expect(
                await ERC20VaultGovernance.strategyTreasury(nftERC20)
            ).to.be.equal(await anotherTreasury.getAddress());
        });

        it("emits", async () => {
            await ERC20VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftERC20, [
                await anotherTreasury.getAddress(),
            ]);
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                ERC20VaultGovernance.connect(admin).commitDelayedStrategyParams(
                    nftERC20
                )
            ).to.emit(ERC20VaultGovernance, "CommitDelayedStrategyParams");
        });
    });
});
