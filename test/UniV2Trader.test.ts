import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { UniV2Trader } from "./types/UniV2Trader";

describe("UniV2Trader", () => { 
    before(async () => {});

    beforeEach(async () => {
        await deployments.fixture();
    });

    describe("#constructor", () => {
        describe("when passed zero address", () => {
            it("reverts with `ZERO_ADDRESS_EXCEPTION`", async () => {
                await expect(
                    (
                        await ethers.getContractFactory("UniV2Trader")
                    ).deploy(ethers.constants.AddressZero)
                ).to.be.revertedWith("AZ");
            });
        });

        describe("happy case", () => {
            it("has correct router address", async () => {
                const { uniswapV2Router02 } = await getNamedAccounts();
                const trader = await (
                    await ethers.getContractFactory("UniV2Trader")
                ).deploy(uniswapV2Router02);
                expect(await trader.router()).to.eql(uniswapV2Router02);
            });
        });
    });

    describe("#swapExactInput", () => {});

    describe("#swapExactOutput", () => {});

    describe("#supportsInterface", () => {
        describe("when passed ERC165 interface", () => {
            it("returns `true`", async () => {});
        });

        describe("when passed ITrader interface", () => {
            it("returns `true`", async () => {});
        });

        describe("when passed zero", () => {
            it("returns `false`", async () => {});
        });
    });
});
