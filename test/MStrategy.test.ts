import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { getNamedAccounts, ethers, deployments } from "hardhat";
import { mint, randomAddress, withSigner } from "./library/Helpers";
import { ERC20, LpIssuer } from "./types";

describe("MStrategy", () => {
    let deploymentFixture: Function;
    let tokens: string[];
    let tokenContracts: ERC20[];

    before(async () => {
        deploymentFixture = await deployments.createFixture(async () => {
            await deployments.fixture();
            const { test } = await getNamedAccounts();

            await withSigner(test, async (s) => {
                const lpIssuer: LpIssuer = await ethers.getContract("LpIssuer");
                tokens = await lpIssuer.vaultTokens();
                const balances = [];
                for (const token of tokens) {
                    const c: ERC20 = await ethers.getContractAt("ERC20", token);
                    tokenContracts.push(c);
                    balances.push(await c.balanceOf(test));
                }
                await lpIssuer.deposit(
                    balances.map((x: BigNumber) => x.div(2)),
                    []
                );
            });
        });
    });
    beforeEach(async () => {
        await deploymentFixture();
    });

    describe("shouldRebalance", () => {
        it("checks if the tokens needs to be rebalanced", async () => {});
    });
});
