import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import { VaultGovernance, ProtocolGovernance } from "./library/Types";
import { deploySubVaultsXGatewayVaultSystem } from "./library/Deployments";
import Exceptions from "./library/Exceptions";
import { randomAddress, sleep, toObject } from "./library/Helpers";
import { BigNumber } from "@ethersproject/bignumber";

describe("GatewayVaultGovernance", () => {
    let deployer: Signer;
    let admin: Signer;
    let treasury: Signer;
    let strategy: Signer;
    let gatewayVaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let gatewayNft: number;
    let deployment: Function;
    let nftERC20: number;

    before(async () => {
        [deployer, admin, treasury, strategy] = await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({
                gatewayVaultGovernance,
                gatewayNft,
                protocolGovernance,
                nftERC20,
            } = await deploySubVaultsXGatewayVaultSystem({
                adminSigner: admin,
                treasury: await treasury.getAddress(),
                vaultOwnerSigner: deployer,
                strategy: await strategy.getAddress(),
            }));
        });
    });

    beforeEach(async () => {
        await deployment();
    });

    describe("constructor", () => {
        it("creates GatewayVaultGovernance", async () => {
            expect(
                await deployer.provider?.getCode(gatewayVaultGovernance.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("stageDelayedStrategyParams", () => {
        //FIXME
        // describe("when redirects.length != vaultTokens.length and redirects.length > 0", () => {
        //     it("reverts", async () => {
        //         await expect(
        //             gatewayVaultGovernance.stageDelayedStrategyParams(
        //                 nftERC20,
        //                 {
        //                     redirects: [1, 2, 3],
        //                     strategyTreasury: await treasury.getAddress(),
        //                 }
        //             )
        //         ).to.be.revertedWith(
        //             Exceptions.REDIRECTS_AND_VAULT_TOKENS_LENGTH
        //         );
        //     });
        // });

        it("sets stageDelayedStrategyParams and emits StageDelayedStrategyParams event", async () => {
            await expect(
                await gatewayVaultGovernance
                    .connect(admin)
                    .stageDelayedStrategyParams(gatewayNft, {
                        redirects: [],
                        strategyTreasury: await treasury.getAddress(),
                    })
            ).to.emit(gatewayVaultGovernance, "StageDelayedStrategyParams");

            expect(
                toObject(
                    await gatewayVaultGovernance.stagedDelayedStrategyParams(
                        gatewayNft
                    )
                )
            ).to.deep.equal({
                redirects: [],
                strategyTreasury: await treasury.getAddress(),
            });
        });
    });

    describe("setStrategyParams", () => {
        it("sets strategy params and emits SetStrategyParams event", async () => {
            await expect(
                gatewayVaultGovernance
                    .connect(admin)
                    .setStrategyParams(gatewayNft, {
                        limits: [1, 2, 3],
                    })
            ).to.emit(gatewayVaultGovernance, "SetStrategyParams");

            expect(
                toObject(
                    await gatewayVaultGovernance
                        .connect(admin)
                        .strategyParams(gatewayNft)
                )
            ).to.deep.equal({
                limits: [
                    BigNumber.from(1),
                    BigNumber.from(2),
                    BigNumber.from(3),
                ],
            });
        });
    });

    describe("commitDelayedStrategyParams", () => {
        it("commits delayed strategy params and emits CommitDelayedStrategyParams event", async () => {
            await gatewayVaultGovernance
                .connect(admin)
                .stageDelayedStrategyParams(gatewayNft, {
                    redirects: [],
                    strategyTreasury: await treasury.getAddress(),
                });
            await sleep(Number(await protocolGovernance.governanceDelay()));
            await expect(
                gatewayVaultGovernance
                    .connect(admin)
                    .commitDelayedStrategyParams(gatewayNft)
            ).to.emit(gatewayVaultGovernance, "CommitDelayedStrategyParams");
            expect(
                toObject(
                    await gatewayVaultGovernance
                        .connect(admin)
                        .delayedStrategyParams(gatewayNft)
                )
            ).to.deep.equal({
                redirects: [],
                strategyTreasury: await treasury.getAddress(),
            });
            expect(
                await gatewayVaultGovernance
                    .connect(admin)
                    .strategyTreasury(gatewayNft)
            ).to.be.equal(await treasury.getAddress());
        });
    });

    describe("delayedStrategyParams", () => {
        describe("when passed unknown nft", () => {
            it("returns empty struct", async () => {
                expect(
                    await gatewayVaultGovernance.delayedStrategyParams(
                        gatewayNft + 42
                    )
                ).to.be.deep.equal([ethers.constants.AddressZero, []]);
            });
        });
    });

    describe("stagedDelayedStrategyParams", () => {
        it("returns params", async () => {
            const address = randomAddress();

            await gatewayVaultGovernance
                .connect(admin)
                .stageDelayedStrategyParams(gatewayNft, {
                    strategyTreasury: address,
                    redirects: [],
                });
            expect(
                await gatewayVaultGovernance.stagedDelayedStrategyParams(
                    gatewayNft
                )
            ).to.be.deep.equal([address, []]);
        });

        describe("when passed unknown nft", () => {
            it("returns empty struct", async () => {
                expect(
                    await gatewayVaultGovernance.stagedDelayedStrategyParams(
                        gatewayNft + 42
                    )
                ).to.be.deep.equal([ethers.constants.AddressZero, []]);
            });
        });
    });

    describe("strategyParams", () => {
        describe("when passed unknown nft", () => {
            it("returns empty struct", async () => {
                expect(
                    await gatewayVaultGovernance.strategyParams(gatewayNft + 42)
                ).to.be.deep.equal([[]]);
            });
        });
    });
});
