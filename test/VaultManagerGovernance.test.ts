// import { expect } from "chai";
// import { deployments, ethers } from "hardhat";
// import { 
//     ContractFactory, 
//     Contract, 
//     Signer 
// } from "ethers";
// import Exceptions from "./library/Exceptions";
// import {
//     deployERC20VaultFactory,
//     deployProtocolGovernance,
//     deployVaultGovernanceFactory,
//     deployVaultManagerGovernance,
// } from "./library/Deployments";
// import {
//     ProtocolGovernance,
//     ERC20VaultFactory,
//     VaultManagerGovernance,

//     ProtocolGovernance_Params,
//     ProtocolGovernance_constructorArgs,
//     VaultGovernanceFactory,
// } from "./library/Types";
// import { sleep, sleepTo } from "./library/Helpers";
// import { BigNumber } from "@ethersproject/bignumber";


// describe("VaultManagerGovernance", () => {
//     let vaultManagerGovernance: VaultManagerGovernance;
//     let protocolGovernance: ProtocolGovernance;
//     let newProtocolGovernance: ProtocolGovernance;
//     let erc20VaultFactory: ERC20VaultFactory;
//     let newERC20VaultFactory: ERC20VaultFactory;
//     let vaultGovernanceFactory: VaultGovernanceFactory;
//     let newVaultGovernanceFactory: VaultGovernanceFactory;
//     let deployer: Signer;
//     let stranger: Signer;
//     let timestamp: number;
//     let gatewayVaultManager: Signer;
//     let protocolTreasury: Signer;

//     beforeEach(async () => {
//         [deployer, stranger, gatewayVaultManager, protocolTreasury] = await ethers.getSigners();

//         erc20VaultFactory = await deployERC20VaultFactory();
//         newERC20VaultFactory = await deployERC20VaultFactory();

//         protocolGovernance = await deployProtocolGovernance({
//             adminSigner: deployer
//         });
//         newProtocolGovernance = await deployProtocolGovernance({
//             adminSigner: deployer
//         });

//         vaultGovernanceFactory = await deployVaultGovernanceFactory();
//         newVaultGovernanceFactory = await deployVaultGovernanceFactory();

//         vaultManagerGovernance = await deployVaultManagerGovernance({
//             constructorArgs: {
//                 permissionless: true,
//                 protocolGovernance: protocolGovernance.address,
//                 factory: erc20VaultFactory.address,
//                 governanceFactory: vaultGovernanceFactory.address,
//             }
//         });
//     });

//     describe("governanceParams", () => {
//         it("passes", async () => {
//             expect(await vaultManagerGovernance.governanceParams()).to.deep.equal(
//                 [
//                     true,
//                     protocolGovernance.address, 
//                     erc20VaultFactory.address,
//                     vaultGovernanceFactory.address,
//                 ]
//             );
//         });
//     });

//     describe("setPendingGovernanceParams", () => {
//         it("role should be governance or delegate", async () => {
//             await protocolGovernance.setPendingClaimAllowlistAdd([ethers.constants.AddressZero]);
//             await newProtocolGovernance.setPendingClaimAllowlistAdd([ethers.constants.AddressZero]);
//             await expect(
//                 vaultManagerGovernance.connect(stranger).setPendingGovernanceParams([
//                     false, 
//                     protocolGovernance.address, 
//                     erc20VaultFactory.address,
//                     vaultGovernanceFactory.address,
//                 ])
//             ).to.be.revertedWith(Exceptions.ADMIN);
//         });

//         it("governance params address should not be zero", async () => {
//             await expect(
//                 vaultManagerGovernance.setPendingGovernanceParams([
//                     false, ethers.constants.AddressZero, erc20VaultFactory.address, vaultGovernanceFactory.address
//                 ])
//             ).to.be.revertedWith(Exceptions.GOVERNANCE_OR_DELEGATE_ADDRESS_ZERO);
//         });

//         it("factory address should not be zero", async () => {
//             await expect(
//                 vaultManagerGovernance.setPendingGovernanceParams([
//                     false, protocolGovernance.address, ethers.constants.AddressZero, vaultGovernanceFactory.address,
//                 ])
//             ).to.be.revertedWith(Exceptions.VAULT_FACTORY_ADDRESS_ZERO);
//         })

//         it("sets correct pending timestamp", async () => {
//             let customProtocol = await deployProtocolGovernance({
//                 constructorArgs: {
//                     admin: await deployer.getAddress(),
//                 },
//                 initializerArgs: {
//                     params:  {
//                         maxTokensPerVault: BigNumber.from(1),
//                         governanceDelay: BigNumber.from(0),
//                         strategyPerformanceFee: BigNumber.from(0),
//                         protocolPerformanceFee: BigNumber.from(1),
//                         protocolExitFee: BigNumber.from(1),
//                         protocolTreasury: await protocolTreasury.getAddress(),
//                         gatewayVaultManager: await gatewayVaultManager.getAddress()
//                     }
//                 },
//                 adminSigner: deployer
//             });
//             await customProtocol.setPendingParams({
//                 maxTokensPerVault: 1,
//                 governanceDelay: 0,
//                 strategyPerformanceFee: 0,
//                 protocolPerformanceFee: 1,
//                 protocolExitFee: 1,
//                 protocolTreasury: ethers.constants.AddressZero,
//                 gatewayVaultManager: ethers.constants.AddressZero
//             });
//             await customProtocol.commitParams();

//             timestamp = Math.ceil(new Date().getTime() / 1000) + 10**8;
//             await sleepTo(timestamp);

//             await vaultManagerGovernance.setPendingGovernanceParams([
//                 false, customProtocol.address, erc20VaultFactory.address, vaultGovernanceFactory.address,
//             ]);
//             console.log(await vaultManagerGovernance.pendingGovernanceParamsTimestamp());
//             expect(
//                 Math.abs(await vaultManagerGovernance.pendingGovernanceParamsTimestamp() - timestamp)
//             ).to.be.lessThanOrEqual(10);
//         });

//         it("emits event SetPendingGovernanceParams", async () => {
//             await expect(
//                 vaultManagerGovernance.setPendingGovernanceParams([                    
//                     false, 
//                     newProtocolGovernance.address, 
//                     erc20VaultFactory.address,
//                     vaultGovernanceFactory.address,
//                 ])
//             ).to.emit(vaultManagerGovernance, "SetPendingGovernanceParams").withArgs([
//                 false,
//                 newProtocolGovernance.address
//             ]);
//         })

//         it("sets pending params", async () => {
//             await vaultManagerGovernance.setPendingGovernanceParams([
//                 false,
//                 newProtocolGovernance.address,
//                 erc20VaultFactory.address,
//                 vaultGovernanceFactory.address,
//             ]);
//             expect(
//                 await vaultManagerGovernance.pendingGovernanceParams()
//             ).to.deep.equal([
//                 false,
//                 newProtocolGovernance.address,
//                 erc20VaultFactory.address,
//                 vaultGovernanceFactory.address,
//             ]);
//         });
//     });

//     describe("commitGovernanceParams", () => {
//         let newProtocolGovernance: Contract;
//         let customProtocol: Contract;

//         beforeEach(async () => {
//             newProtocolGovernance = await deployProtocolGovernance({
//                 adminSigner: deployer
//             });
//             await vaultManagerGovernance.setPendingGovernanceParams([
//                 true,
//                 newProtocolGovernance.address,
//                 erc20VaultFactory.address,
//                 vaultGovernanceFactory.address,
//             ]);
//             customProtocol = await deployProtocolGovernance({
//                 adminSigner: deployer
//             });
//         });
    
//         it("role should be admin", async () => {
//             await expect(
//                 vaultManagerGovernance.connect(stranger).commitGovernanceParams()
//             ).to.be.revertedWith(Exceptions.ADMIN);
//         });
        
//         it("waits governance delay", async () => {
//             const timeout: number = 10000;
//             await customProtocol.setPendingParams({
//                 maxTokensPerVault: 1,
//                 governanceDelay: 0,
//                 strategyPerformanceFee: 0,
//                 protocolPerformanceFee: 1,
//                 protocolExitFee: 1,
//                 protocolTreasury: ethers.constants.AddressZero,
//                 gatewayVaultManager: ethers.constants.AddressZero
//             });
//             await sleep(1);
//             timestamp += 1;
//             await customProtocol.commitParams();

//             timestamp += timeout / 2;
//             await sleep(timeout / 2);

//             await vaultManagerGovernance.setPendingGovernanceParams({
//                 permissionless: false, 
//                 protocolGovernance: newProtocolGovernance.address, 
//                 factory: newERC20VaultFactory.address,
//                 governanceFactory: newVaultGovernanceFactory.address,
//             });

//             await expect(
//                 vaultManagerGovernance.commitGovernanceParams()
//             ).to.be.revertedWith(Exceptions.TIMESTAMP);

//             timestamp += timeout;
//             await sleep(timeout);
//             await expect(vaultManagerGovernance.commitGovernanceParams()).to.not.be.reverted;
//         });
        
//         it("emits CommitGovernanceParams", async () => {
//              await expect(
//                 vaultManagerGovernance.commitGovernanceParams()
//             ).to.emit(vaultManagerGovernance, "CommitGovernanceParams").withArgs([
//                 true,
//                 newProtocolGovernance.address,
//                 erc20VaultFactory.address
//             ]);
//         });

//         it("commits new governance params", async () => {
//             await vaultManagerGovernance.commitGovernanceParams();
//             expect(
//                 await vaultManagerGovernance.governanceParams()
//             ).to.deep.equal([
//                 true, newProtocolGovernance.address, erc20VaultFactory.address, vaultGovernanceFactory.address
//             ]);
//         });
//     });    
// });
