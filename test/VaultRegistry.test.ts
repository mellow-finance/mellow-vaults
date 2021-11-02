import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { ContractFactory, Contract, Signer } from "ethers";
import Exceptions from "./library/Exceptions";
import { 
    deployProtocolGovernance,
    deployVaultRegistryAndProtocolGovernance,
    deployERC20Tokens,
    deployERC20VaultSystem, 
} from "./library/Deployments";
import {
    ERC20,
    ERC20Vault,
    ProtocolGovernance,
    VaultRegistry,
    VaultFactory,
    VaultGovernance,
} from "./library/Types";
import { ProtocolGovernance_Params } from "./library/Types";
import { BigNumber } from "@ethersproject/bignumber";
import { now, sleep, sleepTo, toObject } from "./library/Helpers";
import { Address } from "hardhat-deploy/dist/types";
import { it } from "mocha";
import { eqBy, values } from "ramda";

describe("VaultRegistry", () => {
    let vaults: Address[];
    let nft_vault: Address;
    // let nft: Address;
    let protocolGovernance_Params: ProtocolGovernance_Params;
    let stagedProtocolGovernance: number;
    let vault_size: number;
    let VaultRegistry: VaultRegistry;

    let ProtocolGovernance: ContractFactory;
    let _ProtocolGovernance: ProtocolGovernance;
    let _IncorrectProtocolGovernance: ProtocolGovernance;
    let deployer: Signer;
    let stranger: Signer;
    let user1: Signer;
    let user2: Signer;
    let gatewayVault: Signer;
    let protocolTreasury: Signer;
    let timestamp: number;
    let timeout: number;
    let timeShift: number;
    let params: ProtocolGovernance_Params;
    let paramsZero: ProtocolGovernance_Params;
    let paramsTimeout: ProtocolGovernance_Params;
    let paramsEmpty: ProtocolGovernance_Params;
    let paramsDefault: ProtocolGovernance_Params;
    let defaultGovernanceDelay: number;
    let deploymentFixture: Function;

    let user: Signer;
    let treasury: Signer;
    let protocolGovernanceAdmin: Signer;

    let tokens: ERC20[];
    let vault: ERC20Vault;
    let anotherERC20Vault: ERC20Vault;
    let vaultFactory: VaultFactory;
    let protocolGovernance: ProtocolGovernance;
    let vaultGovernance: VaultGovernance;
    let vaultRegistry: VaultRegistry;
    let nft: number;
    let anotherNft: number;
    let deployment: Function;

    type VaultRegistered_type = {
        nft: number,
        vault: Address,
        owner: Address,
    };

    type paramsGov = {
        permissionless: boolean,
        maxTokensPerVault: BigNumber,
        governanceDelay: BigNumber,
        strategyPerformanceFee: BigNumber,
        protocolPerformanceFee: BigNumber,
        protocolExitFee: BigNumber,
        protocolTreasury: Address,
        vaultRegistry: Address,
    }

    let value: VaultRegistered_type;
    let paramsgov: paramsGov;


    before(async () => {
        [deployer, stranger, user1, user2, gatewayVault, protocolTreasury] =
            await ethers.getSigners();
        timeout = 10 ** 4;
        defaultGovernanceDelay = 1;
        timeShift = 10 ** 10;
        timestamp = now() + timeShift;

        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            return await deployERC20VaultSystem({
                tokensCount: 2,
                adminSigner: deployer,
                treasury: await treasury.getAddress(),
                vaultOwner: await deployer.getAddress(),
            });
        });

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();

            const { vaultRegistry, protocolGovernance } =
                await deployVaultRegistryAndProtocolGovernance({
                    name: "VaultRegistry",
                    symbol: "MVR",
                    adminSigner: deployer,
                    treasury: await protocolTreasury.getAddress(),
                });

            let incorrectProtocolGovernance = deployProtocolGovernance({
                adminSigner: stranger,
            });

            params = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(1),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: await protocolTreasury.getAddress(),
                vaultRegistry: vaultRegistry.address,
            };
            paramsZero = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(0),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: ethers.constants.AddressZero,
                vaultRegistry: ethers.constants.AddressZero,
            };

            paramsEmpty = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(0),
                governanceDelay: BigNumber.from(0),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: ethers.constants.AddressZero,
                vaultRegistry: vaultRegistry.address,
            };

            paramsDefault = {
                permissionless: false,
                maxTokensPerVault: BigNumber.from(0),
                governanceDelay: BigNumber.from(0),
                strategyPerformanceFee: BigNumber.from(0),
                protocolPerformanceFee: BigNumber.from(0),
                protocolExitFee: BigNumber.from(0),
                protocolTreasury: ethers.constants.AddressZero,
                vaultRegistry: ethers.constants.AddressZero,
            };

            paramsTimeout = {
                permissionless: true,
                maxTokensPerVault: BigNumber.from(1),
                governanceDelay: BigNumber.from(timeout),
                strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                protocolExitFee: BigNumber.from(10 ** 9),
                protocolTreasury: await user1.getAddress(),
                vaultRegistry: vaultRegistry.address,
            };

            return { protocolGovernance, vaultRegistry, incorrectProtocolGovernance};
        });
    });

    beforeEach(async () => {
        let { protocolGovernance, vaultRegistry, incorrectProtocolGovernance} = await deploymentFixture();
        _ProtocolGovernance = protocolGovernance;
        VaultRegistry = vaultRegistry;
        _IncorrectProtocolGovernance = incorrectProtocolGovernance;
        sleep(defaultGovernanceDelay);

        ({
            vaultFactory,
            vaultRegistry,
            protocolGovernance,
            vaultGovernance,
            tokens,
            vault,
            nft,
        } = await deployment());

        for (let i: number = 0; i < tokens.length; ++i) {
            await tokens[i].connect(deployer).approve(
                vault.address,
                BigNumber.from(10 ** 9)
                    .mul(BigNumber.from(10 ** 9))
                    .mul(BigNumber.from(10 ** 9))
            );
        }
        await VaultRegistry
            .connect(_ProtocolGovernance.address)
            .approve(await deployer.getAddress(), nft);

            value._nft = nft;
            value._owner = await deployer.getAddress();
            value._vault = vault.address;
    });

    describe("constructor", () => {
        it("Check protocolGovernance address", async () => {
            expect(await VaultRegistry.protocolGovernance()).to.be.eq(_ProtocolGovernance.address);
        });
        it("Check stagedProtocolGovernance", async () => {
            expect(await VaultRegistry.stagedProtocolGovernance()).to.be.eq(ethers.constants.AddressZero);
        });
        it("Check stagedProtocolGovernanceTimestamp", async () => {
            expect(await VaultRegistry.stagedProtocolGovernanceTimestamp()).to.be.eq(BigNumber.from(0));
        });
        it("Check vaultsCount", async () => {
            expect(await VaultRegistry.vaultsCount()).to.be.eq(0);
        });
        it("Checks _vaults", async () => {
            expect((await VaultRegistry.vaults()).length).to.be.eq(0);
        });

        describe("initial params", () => {
            it("registerVault via incorrect sender", async () => {
                expect(await VaultRegistry.connect(_IncorrectProtocolGovernance.address).registerVault(
                    vault.address,
                    await deployer.getAddress()
                )).to.be.revertedWith(Exceptions.ALLOWED_ONLY_VAULT_GOVERNANCE);
            });

            it("registerVault via correct sender", async () => {
                await VaultRegistry.connect(_ProtocolGovernance.address).registerVault(
                    vault.address,
                    await deployer.getAddress()
                );

                expect(await VaultRegistry.vaultsCount()).to.be.eq(1);
                expect((await VaultRegistry.vaults()).length).to.be.eq(1);
                console.log(await VaultRegistry.vaults());
            });

            it("check VaultRegistered event", async () => {
                await expect(VaultRegistry.VaultRegistered(value))
                .to.emit(VaultRegistry, "VaultRegistered")
                .withArgs([
                    value.nft,
                    value.owner,
                    value.vault,
                ]);
            });

            it("stageProtocolGovernance via incorrect vault governance", async () => {
                expect(await VaultRegistry.connect(_IncorrectProtocolGovernance.address).
                stageProtocolGovernance(paramsTimeout)).to.be.revertedWith(Exceptions.ALLOWED_ONLY_VAULT_GOVERNANCE);
            });
            
            describe("stageProtocolGovernance via correct vault governance", () => {
                it("stageProtocolGovernance via correct vault governance", async () => {
                    await VaultRegistry.connect(_ProtocolGovernance.address).
                    stageProtocolGovernance(paramsZero);
                });

                it("commitStagedProtocolGovernance via incorrect vault governance", async () => {
                    expect(await VaultRegistry.connect(_IncorrectProtocolGovernance.address).
                    commitStagedProtocolGovernance()).to.be.revertedWith(Exceptions.ALLOWED_ONLY_VAULT_GOVERNANCE);
                });

                it("commitStagedProtocolGovernance via incorrect timestamp", async () => {
                    expect(await VaultRegistry.connect(_ProtocolGovernance.address).
                    commitStagedProtocolGovernance()).to.be.revertedWith(Exceptions.ALLOWED_ONLY_VAULT_GOVERNANCE);
                });

                it("commitStagedProtocolGovernance via correct vault governance", async () => {
                    await VaultRegistry.connect(_ProtocolGovernance.address).
                    stageProtocolGovernance(paramsDefault);
                    //TODO: Add delay 
                    await VaultRegistry.connect(_ProtocolGovernance.address).
                    commitStagedProtocolGovernance();
                    //Check PG

                });
            })
            
            it("check CommitedProtocolGovernance event", async () => {
                await expect(VaultRegistry.CommitedProtocolGovernance(paramsgov))
                .to.emit(VaultRegistry, "CommitedProtocolGovernance")
                .withArgs([
                    paramsgov.governanceDelay,
                    paramsgov.maxTokensPerVault,
                    paramsgov.permissionless,
                    paramsgov.protocolExitFee,
                    paramsgov.protocolPerformanceFee,
                    paramsgov.protocolTreasury,
                    paramsgov.strategyPerformanceFee,
                    paramsgov.vaultRegistry,
                ]);
            });
        });
    });
});
