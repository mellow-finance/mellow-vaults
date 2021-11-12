import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import { VaultGovernance } from "./library/Types";
import { deploySubVaultsXGatewayVaultSystem } from "./library/Deployments";
import Exceptions from "./library/Exceptions";
import { toObject } from "./library/Helpers";
import { BigNumber } from "@ethersproject/bignumber";

describe("GatewayVaultGovernance", () => {
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let strategy: Signer;
    let gatewayVaultGovernance: VaultGovernance;
    let deployment: Function;
    let nftERC20: number;

    before(async () => {
        [deployer, admin, stranger, treasury, strategy] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({ gatewayVaultGovernance, nftERC20 } =
                await deploySubVaultsXGatewayVaultSystem({
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
        // FIXME
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
                    .stageDelayedStrategyParams(nftERC20, {
                        redirects: [],
                        strategyTreasury: await treasury.getAddress(),
                    })
            ).to.emit(gatewayVaultGovernance, "StageDelayedStrategyParams");

            expect(
                toObject(
                    await gatewayVaultGovernance.stagedDelayedStrategyParams(
                        nftERC20
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
                    .setStrategyParams(nftERC20, {
                        limits: [1, 2, 3],
                    })
            ).to.emit(gatewayVaultGovernance, "SetStrategyParams");

            expect(
                toObject(
                    await gatewayVaultGovernance
                        .connect(admin)
                        .strategyParams(nftERC20)
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
                .stageDelayedStrategyParams(nftERC20, {
                    redirects: [],
                    strategyTreasury: await treasury.getAddress(),
                });
            await expect(
                gatewayVaultGovernance
                    .connect(admin)
                    .commitDelayedStrategyParams(nftERC20)
            ).to.emit(gatewayVaultGovernance, "CommitDelayedStrategyParams");
            expect(
                toObject(
                    await gatewayVaultGovernance
                        .connect(admin)
                        .delayedStrategyParams(nftERC20)
                )
            ).to.deep.equal({
                redirects: [],
                strategyTreasury: await treasury.getAddress(),
            });
            expect(
                await gatewayVaultGovernance
                    .connect(admin)
                    .strategyTreasury(nftERC20)
            ).to.be.equal(await treasury.getAddress());
        });
    });
});
