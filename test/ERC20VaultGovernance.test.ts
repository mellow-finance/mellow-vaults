import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import { VaultGovernance, ProtocolGovernance } from "./library/Types";
import { Contract } from "@ethersproject/contracts";
import { deploySubVaultSystem } from "./library/Deployments";
import { sleep } from "./library/Helpers";

describe("ERC20VaultGovernance", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let treasury: Signer;
    let anotherTreasury: Signer;
    let ERC20VaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let chiefTrader: Contract;
    let nftERC20: number;
    let deployment: Function;

    before(async () => {
        [deployer, admin, treasury, anotherTreasury] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({
                protocolGovernance,
                ERC20VaultGovernance,
                nftERC20,
                chiefTrader,
            } = await deploySubVaultSystem({
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
            ).to.be.deep.equal([
                await treasury.getAddress(),
                chiefTrader.address,
            ]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty params", async () => {
                expect(
                    await ERC20VaultGovernance.delayedStrategyParams(
                        nftERC20 + 1
                    )
                ).to.be.deep.equal([
                    ethers.constants.AddressZero,
                    ethers.constants.AddressZero,
                ]);
            });
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        it("returns params", async () => {
            const address = await treasury.getAddress();
            await ERC20VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftERC20, {
                strategyTreasury: address,
                trader: chiefTrader.address,
            });

            expect(
                await ERC20VaultGovernance.stagedDelayedStrategyParams(nftERC20)
            ).to.be.deep.equal([address, chiefTrader.address]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty params", async () => {
                expect(
                    await ERC20VaultGovernance.stagedDelayedStrategyParams(
                        nftERC20 + 1
                    )
                ).to.be.deep.equal([
                    ethers.constants.AddressZero,
                    ethers.constants.AddressZero,
                ]);
            });
        });
    });

    describe("stageDelayedStrategyParams", () => {
        it("stages DelayedStrategyParams for commit", async () => {
            await ERC20VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftERC20, [
                await anotherTreasury.getAddress(),
                chiefTrader.address,
            ]);
            expect(
                await ERC20VaultGovernance.connect(
                    admin
                ).stagedDelayedStrategyParams(nftERC20)
            ).to.be.deep.equal([
                await anotherTreasury.getAddress(),
                chiefTrader.address,
            ]);
        });

        it("emits", async () => {
            await expect(
                ERC20VaultGovernance.connect(admin).stageDelayedStrategyParams(
                    nftERC20,
                    [await anotherTreasury.getAddress(), chiefTrader.address]
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

    describe("trader", () => {
        it("returns correct trader address", async () => {
            expect(await ERC20VaultGovernance.trader(nftERC20)).to.be.equal(
                chiefTrader.address
            );
        });
    });

    describe("commitDelayedStrategyParams", () => {
        it("commits delayed strategy params", async () => {
            await ERC20VaultGovernance.connect(
                admin
            ).stageDelayedStrategyParams(nftERC20, [
                await anotherTreasury.getAddress(),
                chiefTrader.address,
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
                chiefTrader.address,
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
