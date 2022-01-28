// import { BigNumber } from "@ethersproject/bignumber";
// import { expect } from "chai";
// import { getNamedAccounts, ethers, deployments } from "hardhat";
// import { mint, randomAddress, withSigner } from "./library/Helpers";
// import { contract, setupDefaultContext, TestContext } from "./library/setup";
// import {
//     ERC20,
//     ERC20RootVault,
//     IIntegrationVault,
//     VaultRegistry,
// } from "./types";
// import { MStrategy } from "./types/MStrategy";

// contract<MStrategy, {}, {}>("MStrategy", function () {
//     let tokens: string[];
//     let tokenContracts: ERC20[];
//     let vaultId: number = 0;
//     let kind: "Yearn" | "Aave";
//     let erc20RootNft: number;

//     before(async () => {
//         kind = "Yearn";
//         // @ts-ignore
//         erc20RootNft = kind === "Yearn" ? 3 : 6;
//         this.deploymentFixture = deployments.createFixture(async () => {
//             await deployments.fixture();

//             const erc20RootVaultAddress = await this.vaultRegistry.vaultForNft(
//                 erc20RootNft
//             );
//             const erc20RootVault: ERC20RootVault = await ethers.getContractAt(
//                 "ERC20RootVault",
//                 erc20RootVaultAddress
//             );
//             tokens = await erc20RootVault.vaultTokens();
//             const balances = [];
//             tokenContracts = [];
//             for (const token of tokens) {
//                 const c: ERC20 = await ethers.getContractAt(
//                     "ERC20Token",
//                     token
//                 );
//                 tokenContracts.push(c);
//                 balances.push(await c.balanceOf(this.test.address));
//                 await c
//                     .connect(this.test)
//                     .approve(
//                         erc20RootVault.address,
//                         ethers.constants.MaxUint256
//                     );
//             }
//             await erc20RootVault
//                 .connect(this.test)
//                 .deposit([balances[0].div(3), balances[1].div(3).mul(2)], 0);
//             this.subject = await ethers.getContract(`MStrategy${kind}`);
//             return this.subject;
//         });
//     });
//     beforeEach(async () => {
//         await this.deploymentFixture();
//     });

//     xdescribe("shouldRebalance", () => {
//         it("checks if the tokens needs to be rebalanced", async () => {
//             expect(await this.subject.shouldRebalance(vaultId)).to.be.true;
//         });
//         describe("after rebalance", () => {
//             it("returns false", async () => {
//                 const moneyVaultAddress = await this.vaultRegistry.vaultForNft(
//                     erc20RootNft - 2
//                 );
//                 const moneyVault: IIntegrationVault =
//                     await ethers.getContractAt(
//                         "IIntegrationVault",
//                         moneyVaultAddress
//                     );
//                 const erc20VaultAddress = await this.vaultRegistry.vaultForNft(
//                     erc20RootNft - 1
//                 );
//                 const erc20Vault: IIntegrationVault =
//                     await ethers.getContractAt(
//                         "IIntegrationVault",
//                         erc20VaultAddress
//                     );

//                 await this.subject.rebalance(vaultId);

//                 expect(await this.subject.shouldRebalance(vaultId)).to.be.false;
//             });
//         });
//     });
// });
