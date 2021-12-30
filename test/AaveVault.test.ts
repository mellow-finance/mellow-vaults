// import { expect } from "chai";
// import { deployments, getNamedAccounts, ethers } from "hardhat";
// import { AaveVault } from "./types/AaveVault";
// import { BigNumber } from "@ethersproject/bignumber";
// import {
//     withSigner,
//     depositW9,
//     depositWBTC,
//     sleep,
//     randomAddress,
//     deployVault,
// } from "./library/Helpers";
// import Exceptions from "./library/Exceptions";
// import {
//     AaveVaultGovernance,
//     ERC20,
//     ERC20VaultGovernance,
//     VaultRegistry,
// } from "./types";
// import { CONTRACTS } from "../plugins/contracts/constants";

// xdescribe("AaveVault", () => {
//     let aaveVaultNft: number;
//     let aaveVault: string;
//     let gatewayVaultNft: number;
//     let gatewayVault: string;
//     let erc20Vault: string;
//     let erc20VaultNft: number;
//     let tokens: string[];
//     let aaveVaultContract: AaveVault;
//     let deploymentFixture: Function;

//     before(async () => {
//         deploymentFixture = deployments.createFixture(async () => {
//             await deployments.fixture();
//             const { deployer, weth, usdc } = await getNamedAccounts();
//             tokens = [weth, usdc].map((x) => x.toLowerCase()).sort();
//             ({ nft: aaveVaultNft, address: aaveVault } = await deployVault({
//                 name: "AaveVault",
//                 vaultTokens: tokens,
//                 nftOwner: deployer,
//             }));
//             aaveVaultContract = await ethers.getContractAt(
//                 "AaveVault",
//                 aaveVault
//             );
//             ({ nft: erc20VaultNft, address: erc20Vault } = await deployVault({
//                 name: "ERC20Vault",
//                 vaultTokens: tokens,
//                 nftOwner: deployer,
//             }));
//             ({ nft: gatewayVaultNft, address: gatewayVault } =
//                 await deployVault({
//                     name: "GatewayVault",
//                     subvaultNfts: [aaveVaultNft, erc20VaultNft],
//                     strategyParams: {
//                         limits: [
//                             ethers.constants.MaxUint256,
//                             ethers.constants.MaxUint256,
//                         ],
//                     },
//                     delayedStrategyParams: { redirects: [] },
//                     vaultTokens: tokens,
//                     nftOwner: deployer,
//                 }));
//         });
//     });

//     beforeEach(async () => {
//         await deploymentFixture();
//     });

//     describe("#constructor", () => {
//         it("creates a new contract", async () => {
//             const { deploy, get } = deployments;
//             const { deployer } = await getNamedAccounts();
//             const vaultGovernance = await get("AaveVaultGovernance");
//             await deploy("AaveVault", {
//                 from: deployer,
//                 autoMine: true,
//                 args: [vaultGovernance.address, tokens],
//             });
//         });

//         describe("when passed invalid tokens", () => {
//             it("reverts", async () => {
//                 const { deploy, get } = deployments;
//                 const { deployer } = await getNamedAccounts();
//                 const vaultGovernance = await get("AaveVaultGovernance");
//                 const tokens = [randomAddress(), randomAddress()]
//                     .map((x) => x.toLowerCase())
//                     .sort();
//                 await expect(
//                     deploy("AaveVault", {
//                         from: deployer,
//                         args: [vaultGovernance.address, tokens],
//                     })
//                 ).to.be.reverted;
//             });
//         });
//     });

//     describe("#tvl", () => {
//         describe("when has not initial funds", () => {
//             it("returns zero tvl", async () => {
//                 expect(await aaveVaultContract.tvl()).to.eql([
//                     ethers.constants.Zero,
//                     ethers.constants.Zero,
//                 ]);
//             });
//         });
//     });

//     describe("#updateTvls", () => {
//         describe("when tvl had not change", () => {
//             it("returns the same tvl", async () => {
//                 await expect(aaveVaultContract.updateTvls()).to.not.be.reverted;
//                 expect(await aaveVaultContract.tvl()).to.eql([
//                     ethers.constants.Zero,
//                     ethers.constants.Zero,
//                 ]);
//             });
//         });

//         describe("when tvl changed by direct token transfer", () => {
//             it("tvl remains unchanged before `updateTvls`", async () => {
//                 await depositW9(aaveVault, ethers.utils.parseEther("1"));
//                 expect(await aaveVaultContract.tvl()).to.eql([
//                     ethers.constants.Zero,
//                     ethers.constants.Zero,
//                 ]);
//             });
//         });
//     });

//     describe("#push", () => {
//         describe("when pushed zeroes", () => {
//             it("pushes", async () => {
//                 await withSigner(gatewayVault, async (signer) => {
//                     const { weth, wbtc } = await getNamedAccounts();
//                     const tokens = [weth, wbtc]
//                         .map((t) => t.toLowerCase())
//                         .sort();
//                     await aaveVaultContract
//                         .connect(signer)
//                         .push(tokens, [0, 0], []);
//                 });
//             });
//         });

//         describe("when pushed smth", () => {
//             const amountWBTC = BigNumber.from(10).pow(9);
//             const amount = BigNumber.from(ethers.utils.parseEther("1"));
//             beforeEach(async () => {
//                 await depositW9(aaveVault, amount);
//                 await depositWBTC(aaveVault, amountWBTC.toString());
//             });

//             describe("happy case", () => {
//                 it("approves deposits to lendingPool and updates tvl", async () => {
//                     await withSigner(gatewayVault, async (signer) => {
//                         await expect(
//                             aaveVaultContract
//                                 .connect(signer)
//                                 .push(tokens, [0, amount], [])
//                         ).to.not.be.reverted;
//                         expect(await aaveVaultContract.tvl()).to.eql([
//                             ethers.constants.Zero,
//                             amount,
//                         ]);
//                     });
//                 });

//                 xit("tvl raises with time", async () => {
//                     const { deployer, test } = await getNamedAccounts();
//                     const amounts: BigNumber[] = [];
//                     await withSigner(test, async (s) => {
//                         for (const token of tokens) {
//                             const contract: ERC20 = await ethers.getContractAt(
//                                 "ERC20",
//                                 token
//                             );
//                             const balance = await contract.balanceOf(test);
//                             await contract
//                                 .connect(s)
//                                 .transfer(gatewayVault, balance);
//                             amounts.push(balance);
//                         }
//                     });
//                     await withSigner(gatewayVault, async (signer) => {
//                         for (const token of tokens) {
//                             const contract: ERC20 = await ethers.getContractAt(
//                                 "ERC20",
//                                 token
//                             );
//                             await contract
//                                 .connect(signer)
//                                 .approve(
//                                     aaveVault,
//                                     ethers.constants.MaxUint256
//                                 );
//                         }
//                         await aaveVaultContract
//                             .connect(signer)
//                             .push(tokens, amounts, []);
//                         const [tvlWBTC, tvlWeth] =
//                             await aaveVaultContract.tvl();
//                         // check initial tvls
//                         expect(tvlWBTC.toString()).to.be.equal(
//                             amounts[0].toString()
//                         );
//                         expect(tvlWeth.toString()).to.be.equal(
//                             amounts[1].toString()
//                         );
//                         // wait
//                         await sleep(1000 * 1000 * 1000);
//                         // update tvl
//                         await aaveVaultContract.connect(signer).updateTvls();
//                         const newAmounts = await aaveVaultContract.tvl();
//                         expect(newAmounts[0].gt(amounts[0])).to.be.true;
//                         expect(newAmounts[1].gt(amounts[1])).to.be.true;
//                     });
//                 });
//             });

//             describe("when called twice", () => {
//                 it("not performs approve the second time", async () => {
//                     const amount = ethers.utils.parseEther("1");
//                     await withSigner(gatewayVault, async (signer) => {
//                         await expect(
//                             aaveVaultContract
//                                 .connect(signer)
//                                 .push(tokens, [0, amount], [])
//                         ).to.not.be.reverted;
//                         const { aaveLendingPool } = await getNamedAccounts();
//                         const wethContract: ERC20 = await ethers.getContractAt(
//                             "WERC20Test",
//                             tokens[1]
//                         );
//                         // allowance increased
//                         expect(
//                             await wethContract.allowance(
//                                 aaveVault,
//                                 aaveLendingPool
//                             )
//                         ).to.be.equal(ethers.constants.MaxUint256);
//                         // insure coverage of _approveIfNessesary
//                         await depositW9(aaveVault, amount);
//                         await expect(
//                             aaveVaultContract
//                                 .connect(signer)
//                                 .push(tokens, [0, amount], [])
//                         ).to.not.be.reverted;
//                     });
//                 });
//             });
//         });
//     });

//     describe("#pull", () => {
//         const w9Amount = ethers.utils.parseEther("10");

//         beforeEach(async () => {
//             await deployments.fixture();
//             await depositW9(aaveVault, w9Amount);
//         });

//         describe("when nothing is pushed", () => {
//             it("nothing is pulled", async () => {
//                 await withSigner(gatewayVault, async (signer) => {
//                     await aaveVaultContract
//                         .connect(signer)
//                         .pull(erc20Vault, tokens, [0, 0], []);

//                     await expect(
//                         aaveVaultContract
//                             .connect(signer)
//                             .pull(erc20Vault, tokens, [0, 0], [])
//                     ).to.not.be.reverted;
//                     const wethContract = await ethers.getContractAt(
//                         "WERC20Test",
//                         tokens[1]
//                     );
//                     expect(await wethContract.balanceOf(aaveVault)).to.eql(
//                         w9Amount
//                     );
//                 });
//             });
//         });

//         describe("when pushed smth", () => {
//             const amount = ethers.utils.parseEther("1");

//             beforeEach(async () => {
//                 await deployments.fixture();
//                 await depositW9(aaveVault, amount);
//                 await withSigner(gatewayVault, async (signer) => {
//                     await expect(
//                         aaveVaultContract
//                             .connect(signer)
//                             .push(tokens, [0, amount], [])
//                     ).to.not.be.reverted;
//                 });
//             });

//             xit("smth pulled", async () => {
//                 await withSigner(gatewayVault, async (signer) => {
//                     await aaveVaultContract
//                         .connect(signer)
//                         .pull(erc20Vault, tokens, [0, amount], []);
//                     const wethContract: ERC20 = await ethers.getContractAt(
//                         "ERC20",
//                         tokens[1]
//                     );
//                     expect(await wethContract.balanceOf(erc20Vault)).to.eql(
//                         amount
//                     );
//                 });
//             });

//             describe("when pull amount is greater then actual balance", () => {
//                 xit("executes", async () => {
//                     await withSigner(gatewayVault, async (signer) => {
//                         await expect(
//                             aaveVaultContract
//                                 .connect(signer)
//                                 .pull(
//                                     erc20Vault,
//                                     tokens,
//                                     [0, amount.mul(2)],
//                                     []
//                                 )
//                         ).to.be.revertedWith("5"); // aave lending pool: insufficient balance
//                     });
//                 });
//             });
//         });
//     });
// });
