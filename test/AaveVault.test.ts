// import { expect } from "chai";
// import { ethers, network } from "hardhat";
// import { ContractFactory, Contract, Signer } from "ethers";
// import Exceptions from "./library/Exceptions";
// import { BigNumber } from "@ethersproject/bignumber";
// import {
//     AaveVaultFactory,
//     AaveVault,
//     ERC20,
// } from "./library/Types";
// import { deployAaveVaultSystem } from "./library/Deployments";
// import {
//     ProtocolGovernance,
//     VaultGovernance,
// } from "./library/Types";

// describe("AaveVaultFactory", function () {
//     this.timeout(100 * 1000);

//     let deployer: Signer;
//     let stranger: Signer;
//     let treasury: Signer;
//     let user: Signer;
//     let protocolGovernanceAdmin: Signer;

//     let protocolGovernance: ProtocolGovernance;
//     let tokens: ERC20[];
//     let AaveVault: AaveVault;
//     let AaveVaultFactory: AaveVaultFactory;

//     let nft: number;
//     let vaultGovernance: VaultGovernance;

//     before(async () => {
//         [deployer, stranger, treasury, protocolGovernanceAdmin] =
//             await ethers.getSigners();
//         ({
//             AaveVault,
//             AaveVaultFactory,
//             vaultGovernance,
//             protocolGovernance,
//             tokens,
//             nft,
//         } = await deployAaveVaultSystem({
//             protocolGovernanceAdmin: protocolGovernanceAdmin,
//             treasury: await treasury.getAddress(),
//             tokensCount: 10,
//             permissionless: true,
//             vaultManagerName: "vault manager",
//             vaultManagerSymbol: "Aavevm ¯\\_(ツ)_/¯",
//         }));
//     });
// });
