// import { expect } from "chai";
// import {
//     ethers,
//     deployments
// } from "hardhat";
// import { 
//     ContractFactory, 
//     Contract, 
//     Signer 
// } from "ethers";
// import {
//     ERC20,
//     ERC20Vault,
//     ERC20VaultManager,
//     ERC20VaultFactory,
//     VaultGovernance,
//     VaultGovernanceFactory,
//     ProtocolGovernance
// } from "./library/Types";
// import { deployERC20VaultSystem } from "./library/Fixtures";
// import { sleepTo } from "./library/Helpers";
// import Exceptions from "./library/Exceptions";

// describe("ERC20Vault", function() {
//     describe("when permissionless is set to true", () => {
//         let deployer: Signer;
//         let stranger: Signer;
//         let treasury: Signer;
//         let protocolGovernanceAdmin: Signer;

//         let tokens: ERC20[];
//         let erc20Vault: ERC20Vault;
//         let erc20VaultManager: ERC20VaultManager;
//         let erc20VaultFactory: ERC20VaultFactory;
//         let vaultGovernance: VaultGovernance;
//         let vaultGovernanceFactory: VaultGovernanceFactory;
//         let protocolGovernance: ProtocolGovernance;

//         let nft: number;

//         before(async () => {
//             [
//                 deployer,
//                 stranger,
//                 treasury,
//                 protocolGovernanceAdmin,
//             ] = await ethers.getSigners();
            
//             ({ 
//                 erc20Vault, 
//                 erc20VaultManager, 
//                 erc20VaultFactory, 
//                 vaultGovernance, 
//                 vaultGovernanceFactory, 
//                 protocolGovernance, 
//                 nft 
//             } = await deployERC20VaultSystem({
//                 protocolGovernanceAdmin: protocolGovernanceAdmin,
//                 treasury: await treasury.getAddress(),
//                 tokensCount: 10,
//                 permissionless: true,
//                 vaultManagerName: "vault manager ¯\_(ツ)_/¯",
//                 vaultManagerSymbol: "erc20vm"
//             }));
//         });

//         describe("constructor", () => {
//             it("works", async () => {
//                 console.log("really works!");
//             });
//         });
//     });
// });
