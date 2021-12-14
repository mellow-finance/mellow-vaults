import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { UniV2Trader } from "./types/UniV2Trader";
import {
    ERC165_INTERFACE_ID,
    TRADER_INTERFACE_ID,
    ZERO_INTERFACE_ID,
} from "./library/Constants";

describe("UniV2Trader", () => {
    let deploymentFixture: Function;
    let uniV2Trader: UniV2Trader;
    before(async () => {
        const { get } = deployments;
        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            uniV2Trader = await ethers.getContractAt(
                "UniV2Trader",
                (
                    await get("UniV2Trader")
                ).address
            );
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
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
            it("returns `true`", async () => {
                expect(await uniV2Trader.supportsInterface(ERC165_INTERFACE_ID))
                    .to.be.true;
            });
        });

        describe("when passed ITrader interface", () => {
            it("returns `true`", async () => {
                expect(await uniV2Trader.supportsInterface(TRADER_INTERFACE_ID))
                    .to.be.true;
            });
        });

        describe("when passed zero", () => {
            it("returns `false`", async () => {
                expect(await uniV2Trader.supportsInterface(ZERO_INTERFACE_ID))
                    .to.be.false;
            });
        });
    });
});
