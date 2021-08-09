import { ethers } from "hardhat";
import { Signer, Contract, ContractFactory } from "ethers";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { prop, sortBy } from "ramda";

describe("TokensVault", function () {
  let accounts: SignerWithAddress[];
  let TokensVault: ContractFactory;
  let ERC20: ContractFactory;
  let tokens: Contract[];

  before(async function () {
    accounts = await ethers.getSigners();
    TokensVault = await ethers.getContractFactory("TokensVault");
    ERC20 = await ethers.getContractFactory("ERC20Mock");
    tokens = [];
    for (let i = 0; i < 3; i++) {
      const token = await ERC20.deploy(`token${i}`, `T${i}`);
      await token.mint(
        accounts[0].address,
        ethers.constants.WeiPerEther.mul(1000)
      );
      tokens.push(token);
    }
  });

  describe("constructor", () => {
    it("creates a contracts with tokens sorted", async () => {
      for (const tks of [
        [tokens[0].address, tokens[1].address],
        [tokens[2].address, tokens[1].address, tokens[0].address],
      ]) {
        const tokensVault = await TokensVault.deploy(tks);
        expect(await tokensVault.tokens()).to.eql(tks.sort());
      }
    });
    describe("when tokens are repeated", () => {
      it("reverts", async () => {
        for (const tks of [
          [tokens[0].address, tokens[0].address],
          [tokens[2].address, tokens[1].address, tokens[2].address],
        ]) {
          await expect(TokensVault.deploy(tks)).to.be.revertedWith("TE");
        }
      });
    });
    describe("when tokens are empty", () => {
      it("reverts", async () => {
        await expect(TokensVault.deploy([])).to.be.revertedWith("ETL");
      });
    });
  });

  describe("#tokens", async function () {
    it("returns sorted list of tokens under management", async () => {
      for (const tks of [
        [tokens[0].address, tokens[1].address],
        [tokens[2].address, tokens[1].address, tokens[0].address],
      ]) {
        const tokensVault = await TokensVault.deploy(tks);
        expect(await tokensVault.tokens()).to.eql(tks.sort());
      }
    });
  });

  describe("#tokensCount", () => {
    it("returns the number of tokens", async () => {
      for (const tks of [
        [tokens[0].address],
        [tokens[0].address, tokens[1].address],
        [tokens[2].address, tokens[1].address, tokens[0].address],
      ]) {
        const tokensVault = await TokensVault.deploy(tks);
        expect(await tokensVault.tokensCount()).to.eq(tks.length);
      }
    });
  });

  describe("#ownTokenAmounts", () => {
    it("returns token balances", async () => {
      const tokensVault = await TokensVault.deploy([
        tokens[0].address,
        tokens[1].address,
        tokens[2].address,
      ]);
      for (let i = 0; i < 3; i++)
        await tokens[i].mint(
          tokensVault.address,
          ethers.constants.WeiPerEther.mul(i + 1)
        );
      const tks = sortBy(prop("address"), tokens);
      const expected = [];
      for (let i = 0; i < 3; i++) {
        const bal = await tks[i].balanceOf(tokensVault.address);
        expected.push(bal);
      }
      expect(await tokensVault.ownTokenAmounts()).to.eql(expected);
    });
  });
});
