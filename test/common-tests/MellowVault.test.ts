// import hre from "hardhat";
// import { expect } from "chai";
// import { ethers, getNamedAccounts, deployments } from "hardhat";
// import { BigNumber } from "@ethersproject/bignumber";
// import {
//     encodeToBytes,
//     mint,
//     randomAddress,
//     sleep,
//     withSigner,
// } from "../library/Helpers";
// import { contract } from "../library/setup";
// import { ERC20RootVault, ERC20Vault, MellowVault } from "../types";
// import {
//     combineVaults,
//     PermissionIdsLibrary,
//     setupVault,
// } from "..//deploy/0000_utils";
// import { integrationVaultBehavior } from "../behaviors/integrationVault";
// import {
//     INTEGRATION_VAULT_INTERFACE_ID,
//     YEARN_VAULT_INTERFACE_ID,
// } from "../library/Constants";
// import Exceptions from "../library/Exceptions";
//
// type CustomContext = {
//     erc20Vault: ERC20Vault;
//     erc20RootVault: ERC20RootVault;
//     curveRouter: string;
//     preparePush: () => any;
// };
//
// type DeployOptions = {};
//
// contract<MellowVault, DeployOptions, CustomContext>("MellowVault", function () {
//     before(async () => {
//         this.deploymentFixture = deployments.createFixture(
//             async (_, __?: DeployOptions) => {
//                 await deployments.fixture();
//                 const { read } = deployments;
//
//                 const { curveRouter } = await getNamedAccounts();
//                 this.curveRouter = curveRouter;
//                 this.preparePush = async () => {
//                     await sleep(0);
//                 };
//
//                 const tokens = [this.weth.address, this.usdc.address]
//                     .map((t) => t.toLowerCase())
//                     .sort();
//
//                 const startNft =
//                     (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
//
//                 let mellowVaultNft = startNft;
//                 let erc20VaultNft = startNft + 1;
//
//                 await setupVault(hre, mellowVaultNft, "MellowVaultGovernance", {
//                     createVaultArgs: [
//                         tokens,
//                         this.deployer.address,
//                         ethers.constants.AddressZero,
//                     ],
//                 });
//                 await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
//                     createVaultArgs: [tokens, this.deployer.address],
//                 });
//
//                 await combineVaults(
//                     hre,
//                     erc20VaultNft + 1,
//                     [erc20VaultNft, mellowVaultNft],
//                     this.deployer.address,
//                     this.deployer.address
//                 );
//                 const erc20Vault = await read(
//                     "VaultRegistry",
//                     "vaultForNft",
//                     erc20VaultNft
//                 );
//                 const mellowVault = await read(
//                     "VaultRegistry",
//                     "vaultForNft",
//                     mellowVaultNft
//                 );
//                 const erc20RootVault = await read(
//                     "VaultRegistry",
//                     "vaultForNft",
//                     erc20VaultNft + 1
//                 );
//
//                 this.erc20Vault = await ethers.getContractAt(
//                     "ERC20Vault",
//                     erc20Vault
//                 );
//
//                 this.subject = await ethers.getContractAt(
//                     "MellowVault",
//                     mellowVault
//                 );
//
//                 this.erc20RootVault = await ethers.getContractAt(
//                     "ERC20RootVault",
//                     erc20RootVault
//                 );
//                 let address = `0x${this.erc20RootVault.address
//                     .substr(2)
//                     .padStart(64, "0")}`;
//                 await ethers.provider.send("hardhat_setStorageAt", [
//                     this.subject.address,
//                     "0x5", // address of vault
//                     address,
//                 ]);
//
//                 for (let address of [
//                     this.deployer.address,
//                     this.subject.address,
//                     this.erc20Vault.address,
//                 ]) {
//                     await mint(
//                         "USDC",
//                         address,
//                         BigNumber.from(10).pow(18).mul(3000)
//                     );
//                     await mint(
//                         "WETH",
//                         address,
//                         BigNumber.from(10).pow(18).mul(3000)
//                     );
//                     await this.weth.approve(
//                         address,
//                         ethers.constants.MaxUint256
//                     );
//                     await this.usdc.approve(
//                         address,
//                         ethers.constants.MaxUint256
//                     );
//                 }
//
//                 return this.subject;
//             }
//         );
//     });
//
//     beforeEach(async () => {
//         await this.deploymentFixture();
//     });
//
//     describe("#tvl", () => {
//         beforeEach(async () => {
//             await withSigner(this.subject.address, async (signer) => {
//                 await this.usdc
//                     .connect(signer)
//                     .approve(
//                         this.deployer.address,
//                         ethers.constants.MaxUint256
//                     );
//                 await this.weth
//                     .connect(signer)
//                     .approve(
//                         this.deployer.address,
//                         ethers.constants.MaxUint256
//                     );
//
//                 await this.usdc
//                     .connect(signer)
//                     .transfer(
//                         this.deployer.address,
//                         await this.usdc.balanceOf(this.subject.address)
//                     );
//                 await this.weth
//                     .connect(signer)
//                     .transfer(
//                         this.deployer.address,
//                         await this.weth.balanceOf(this.subject.address)
//                     );
//             });
//         });
//
//         it("returns total value locked", async () => {
//             await mint(
//                 "USDC",
//                 this.subject.address,
//                 BigNumber.from(10).pow(18).mul(3000)
//             );
//             await mint(
//                 "WETH",
//                 this.subject.address,
//                 BigNumber.from(10).pow(18).mul(3000)
//             );
//
//             await this.preparePush();
//             await this.subject.push(
//                 [this.usdc.address, this.weth.address],
//                 [
//                     BigNumber.from(10).pow(6).mul(3000),
//                     BigNumber.from(10).pow(18).mul(1),
//                 ],
//                 encodeToBytes(["uint256"], [BigNumber.from(1)])
//             );
//             const result = await this.subject.tvl();
//             for (let amountsId = 0; amountsId < 2; ++amountsId) {
//                 for (let tokenId = 0; tokenId < 2; ++tokenId) {
//                     expect(result[amountsId][tokenId]).gt(0);
//                 }
//             }
//         });
//
//         describe("edge cases:", () => {
//             describe("when there are no initial funds", () => {
//                 it("returns zeroes", async () => {
//                     const result = await this.subject.tvl();
//                     for (let amountsId = 0; amountsId < 2; ++amountsId) {
//                         for (let tokenId = 0; tokenId < 2; ++tokenId) {
//                             expect(result[amountsId][tokenId]).eq(0);
//                         }
//                     }
//                 });
//             });
//         });
//     });
//
//     describe("#initialize", () => {
//         beforeEach(async () => {
//             this.nft = await ethers.provider.send("eth_getStorageAt", [
//                 this.subject.address,
//                 "0x4", // address of _nft
//             ]);
//             await ethers.provider.send("hardhat_setStorageAt", [
//                 this.subject.address,
//                 "0x4", // address of _nft
//                 "0x0000000000000000000000000000000000000000000000000000000000000000",
//             ]);
//         });
//
//         it("emits Initialized event", async () => {
//             await withSigner(
//                 this.mellowVaultGovernance.address,
//                 async (signer) => {
//                     await expect(
//                         this.subject
//                             .connect(signer)
//                             .initialize(
//                                 this.nft,
//                                 [this.usdc.address, this.weth.address],
//                                 this.erc20RootVault.address
//                             )
//                     ).to.emit(this.subject, "Initialized");
//                 }
//             );
//         });
//         it("initializes contract successfully", async () => {
//             await withSigner(
//                 this.mellowVaultGovernance.address,
//                 async (signer) => {
//                     await expect(
//                         this.subject
//                             .connect(signer)
//                             .initialize(
//                                 this.nft,
//                                 [this.usdc.address, this.weth.address],
//                                 this.erc20RootVault.address
//                             )
//                     ).to.not.be.reverted;
//                 }
//             );
//         });
//
//         describe("edge cases:", () => {
//             describe("when vault's nft is not 0", () => {
//                 it(`reverts with ${Exceptions.INIT}`, async () => {
//                     await ethers.provider.send("hardhat_setStorageAt", [
//                         this.subject.address,
//                         "0x4", // address of _nft
//                         "0x0000000000000000000000000000000000000000000000000000000000000007",
//                     ]);
//                     await expect(
//                         this.subject.initialize(
//                             this.nft,
//                             [this.usdc.address, this.weth.address],
//                             this.erc20RootVault.address
//                         )
//                     ).to.be.revertedWith(Exceptions.INIT);
//                 });
//             });
//             describe("when tokens are not sorted", () => {
//                 it(`reverts with ${Exceptions.INVARIANT}`, async () => {
//                     await expect(
//                         this.subject.initialize(
//                             this.nft,
//                             [this.weth.address, this.usdc.address],
//                             this.erc20RootVault.address
//                         )
//                     ).to.be.revertedWith(Exceptions.INVARIANT);
//                 });
//             });
//             describe("when tokens are not unique", () => {
//                 it(`reverts with ${Exceptions.INVARIANT}`, async () => {
//                     await expect(
//                         this.subject.initialize(
//                             this.nft,
//                             [this.weth.address, this.weth.address],
//                             this.erc20RootVault.address
//                         )
//                     ).to.be.revertedWith(Exceptions.INVARIANT);
//                 });
//             });
//             describe("when setting zero nft", () => {
//                 it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
//                     await expect(
//                         this.subject.initialize(
//                             0,
//                             [this.usdc.address, this.weth.address],
//                             this.erc20RootVault.address
//                         )
//                     ).to.be.revertedWith(Exceptions.VALUE_ZERO);
//                 });
//             });
//             describe("when token has no permission to become a vault token", () => {
//                 it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
//                     await this.protocolGovernance
//                         .connect(this.admin)
//                         .revokePermissions(this.usdc.address, [
//                             PermissionIdsLibrary.ERC20_VAULT_TOKEN,
//                         ]);
//                     await withSigner(
//                         this.mellowVaultGovernance.address,
//                         async (signer) => {
//                             await expect(
//                                 this.subject
//                                     .connect(signer)
//                                     .initialize(
//                                         this.nft,
//                                         [this.usdc.address, this.weth.address],
//                                         this.erc20RootVault.address
//                                     )
//                             ).to.be.revertedWith(Exceptions.FORBIDDEN);
//                         }
//                     );
//                 });
//             });
//         });
//     });
//
//     integrationVaultBehavior.call(this, {});
// });
