import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { getNamedAccounts, ethers, deployments } from "hardhat";
import { mint, randomAddress, withSigner } from "./library/Helpers";
import { ERC20, LpIssuer, VaultRegistry } from "./types";
import { MStrategy } from "./types/MStrategy";

describe("MStrategy", () => {
    let deploymentFixture: Function;
    let tokens: string[];
    let tokenContracts: ERC20[];
    let lpIssuer: LpIssuer;
    let mStrategy: MStrategy;
    let vaultId: number;

    before(async () => {
        vaultId = 0;
        deploymentFixture = await deployments.createFixture(async () => {
            await deployments.fixture();

            const { test } = await getNamedAccounts();

            mStrategy = await ethers.getContract("MStrategy");

            await withSigner(test, async (s) => {
                const vaultRegistry: VaultRegistry = await ethers.getContract(
                    "VaultRegistry"
                );
                const vaultsCount = await vaultRegistry.vaultsCount();
                const lpIssuerAddress = await vaultRegistry.vaultForNft(
                    vaultsCount
                );
                lpIssuer = await ethers.getContractAt(
                    "LpIssuer",
                    lpIssuerAddress
                );
                tokens = await lpIssuer.vaultTokens();
                const balances = [];
                tokenContracts = [];
                for (const token of tokens) {
                    const c: ERC20 = await ethers.getContractAt("ERC20", token);
                    tokenContracts.push(c);
                    balances.push(await c.balanceOf(test));
                    await c
                        .connect(s)
                        .approve(lpIssuer.address, ethers.constants.MaxUint256);
                }
                await lpIssuer
                    .connect(s)
                    .deposit(
                        [balances[0].div(3), balances[1].div(3).mul(2)],
                        []
                    );
            });
        });
    });
    beforeEach(async () => {
        await deploymentFixture();
    });

    describe("shouldRebalance", () => {
        it("checks if the tokens needs to be rebalanced", async () => {
            expect(await mStrategy.shouldRebalance(vaultId)).to.be.true;
        });
        describe("after rebalance", () => {
            it("returns false", async () => {
                await mStrategy.rebalance(vaultId);
                const { erc20Vault, moneyVault } =
                    await mStrategy.vaultImmutableParams(vaultId);
                const tvls = [];
                for (const vault of [erc20Vault, moneyVault]) {
                    const c = await ethers.getContractAt("IVault", vault);
                    tvls.push(await c.tvl());
                }
                const tvlSum = [
                    tvls[0][0].add(tvls[1][0]),
                    tvls[0][1].add(tvls[1][1]),
                ];
                console.log(
                    "ERC20",
                    tvls[0].map((x: any) => x.toString())
                );
                console.log(
                    "Money",
                    tvls[1].map((x: any) => x.toString())
                );
                console.log(
                    "Total",
                    tvlSum.map((x: any) => x.toString())
                );

                expect(await mStrategy.shouldRebalance(vaultId)).to.be.false;
            });
        });
    });
});
