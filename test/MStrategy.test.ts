import { expect } from "chai";
import { getNamedAccounts, ethers } from "hardhat";
import { mint, randomAddress } from "./library/Helpers";
import { ERC20 } from "./types";

describe("MStrategy", () => {
    it("can mint", async () => {
        const address = randomAddress();
        await mint("WBTC", address, 1000);
        const { wbtc } = await getNamedAccounts();
        const c: ERC20 = await ethers.getContractAt("ERC20", wbtc);
        expect(await c.balanceOf(address)).to.eq(1000);
    });
});
