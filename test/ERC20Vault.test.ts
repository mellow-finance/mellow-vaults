import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Signer } from "ethers";
import {
    ERC20,
    ERC20Vault,
    ERC20VaultFactory,
    VaultManager,
    VaultGovernance,
    VaultGovernanceFactory,
    ProtocolGovernance,
    ERC20Test_constructorArgs
} from "./library/Types";
import {
    deployERC20Tokens,
    deployERC20VaultFactory,
    deployProtocolGovernance,
    deployVaultGovernanceFactory,
    deployVaultManagerTest
} from "./library/Deployments";
import { sortContractsByAddresses } from "./library/Helpers";
import Exceptions from "./library/Exceptions";

describe("ERC20Vault", function () {
    describe("when permissionless is set to true", () => {
        let deployer: Signer;
        let user: Signer;
        let stranger: Signer;
        let treasury: Signer;
        let protocolGovernanceAdmin: Signer;

        let tokens: ERC20[];
        let erc20Vault: ERC20Vault;
        let erc20VaultFactory: ERC20VaultFactory;
        let erc20VaultManager: VaultManager;
        let vaultGovernance: VaultGovernance;
        let vaultGovernanceFactory: VaultGovernanceFactory;
        let protocolGovernance: ProtocolGovernance;

        let nft: number;

        before(async () => {
            [
                deployer,
                user,
                stranger,
                treasury,
                protocolGovernanceAdmin,
            ] = await ethers.getSigners();

            let options = {
                protocolGovernanceAdmin: protocolGovernanceAdmin,
                treasury: await treasury.getAddress(),
                tokensCount: 2,
                permissionless: true,
                vaultManagerName: "vault manager ¯\\_(ツ)_/¯",
                vaultManagerSymbol: "erc20vm"
            }

            let token_constructorArgs: ERC20Test_constructorArgs[] = [];
            for (let i: number = 0; i < options!.tokensCount; ++i) {
                token_constructorArgs.push({
                    name: "Test Token",
                    symbol: `TEST_${i}`
                });
            }
            tokens = await deployERC20Tokens({
                constructorArgs: token_constructorArgs
            });
            // sort tokens by address using `sortAddresses` function
            const tokensSorted: ERC20[] = sortContractsByAddresses(tokens);

            protocolGovernance = await deployProtocolGovernance({
                constructorArgs: {
                    admin: await options!.protocolGovernanceAdmin.getAddress(),
                    params: {
                        maxTokensPerVault: 10,
                        governanceDelay: 1,

                        strategyPerformanceFee: 10 ** 9,
                        protocolPerformanceFee: 10 ** 9,
                        protocolExitFee: 10 ** 9,
                        protocolTreasury: ethers.constants.AddressZero,
                        gatewayVaultManager: ethers.constants.AddressZero,
                    }
                },
                adminSigner: options!.protocolGovernanceAdmin
            });

            vaultGovernanceFactory = await deployVaultGovernanceFactory();

            erc20VaultFactory = await deployERC20VaultFactory();

            erc20VaultManager = await deployVaultManagerTest({
                constructorArgs: {
                    name: options!.vaultManagerName ?? "ERC20VaultManager",
                    symbol: options!.vaultManagerSymbol ?? "E20VM",
                    factory: erc20VaultFactory.address,
                    governanceFactory: vaultGovernanceFactory.address,
                    permissionless: options!.permissionless,
                    governance: protocolGovernance.address
                }
            });

            vaultGovernance = await (await ethers.getContractFactory("VaultGovernance")).deploy(
                tokensSorted.map(t => t.address),
                erc20VaultManager.address,
                options!.treasury,
                await protocolGovernanceAdmin.getAddress()
            );
            await vaultGovernance.deployed();

            erc20Vault = await (await ethers.getContractFactory("ERC20Vault")).deploy(
                vaultGovernance.address
            )
            await erc20Vault.deployed();

            nft = await erc20VaultManager.callStatic.mintVaultNft(erc20Vault.address);
            await erc20VaultManager.mintVaultNft(erc20Vault.address);
        });

        describe("constructor", () => {

            it("has correct vaultGovernance address", async () => {
                expect(await erc20Vault.vaultGovernance()).to.equal(vaultGovernance.address);
            });

            it("has zero tvl", async () => {
                expect(await erc20Vault.tvl()).to.deep.equal([BigNumber.from(0), BigNumber.from(0)]);
            });

            it("has zero earnings", async () => {
                expect(await erc20Vault.earnings()).to.deep.equal([BigNumber.from(0), BigNumber.from(0)]);
            });

            it("nft owner", async () => {
                expect(await erc20VaultManager.ownerOf(nft)).to.equals(await deployer.getAddress());
            });
        });

        describe("push", () => {
            it("when not approved nor owner", async () => {
                await expect(erc20Vault.connect(stranger).push(
                    [tokens[0].address], 
                    [BigNumber.from(1)],
                    false,
                    []
                )).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
            });

            it("when tokens and tokenAmounts lengthes do not match", async () => {
                await expect(erc20Vault.push(
                    [tokens[0].address], 
                    [BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
            });

            it("when tokens not sorted", async () => {
                await expect(erc20Vault.push(
                    [tokens[1].address, tokens[0].address], 
                    [BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            })

            it("when tokens not unique", async () => {
                await expect(erc20Vault.push(
                    [tokens[0].address, tokens[0].address],
                    [BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });

            it("when tokens not sorted nor unique", async () => {
                await expect(erc20Vault.push(
                    [tokens[1].address, tokens[0].address, tokens[1].address],
                    [BigNumber.from(1), BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });

            it("passes", async () => {
                const amounts = await erc20Vault.callStatic.push(
                    [tokens[0].address], 
                    [BigNumber.from(10**9)],
                    true,
                    []
                );
                expect(amounts).to.deep.equal([BigNumber.from(10**9)]);
            });
        });

        describe("pull", () => {

        });

        describe("transferAndPush", () => {
            before(async () => {
                for (let i: number = 0; i < tokens.length; ++i) {
                    await tokens[i].connect(deployer).approve(
                        erc20Vault.address, 
                        BigNumber.from(10**9).mul(BigNumber.from(10**9))
                    );
                }
            });

            it("when not approved nor owner", async () => {
                await expect(erc20Vault.connect(stranger).transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address], 
                    [BigNumber.from(1)],
                    false,
                    []
                )).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
            });

            it("when tokens and tokenAmounts lengthes do not match", async () => {
                await expect(erc20Vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address], 
                    [BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
            });

            it("when tokens not sorted", async () => {
                await expect(erc20Vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[1].address, tokens[0].address], 
                    [BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            })

            it("when tokens not unique", async () => {
                await expect(erc20Vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address, tokens[0].address],
                    [BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });

            it("when tokens not sorted nor unique", async () => {
                await expect(erc20Vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[1].address, tokens[0].address, tokens[1].address],
                    [BigNumber.from(1), BigNumber.from(1), BigNumber.from(1)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });

            it("when ok", async () => {
                expect(await erc20Vault.callStatic.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address], 
                    [BigNumber.from(10**9)],
                    true,
                    []
                )).to.deep.equal([BigNumber.from(10**9)]);
            });

            it("when not enough balance", async () => {
                await tokens[0].transfer(await user.getAddress(), BigNumber.from(10**3));
                await tokens[0].connect(user).approve(
                    erc20Vault.address,
                    BigNumber.from(10**3)
                );
                await expect(erc20Vault.transferAndPush(
                    await user.getAddress(),
                    [tokens[0].address], 
                    [BigNumber.from(10**9)],
                    true,
                    []
                )).to.be.revertedWith(Exceptions.ERC20_INSUFFICIENT_BALANCE);
            });
        });

        describe("tvl", () => {
            before(async () => {
                for (let i: number = 0; i < tokens.length; ++i) {
                    await tokens[i].connect(deployer).approve(
                        erc20Vault.address, 
                        BigNumber.from(10**9).mul(BigNumber.from(10**9))
                    );
                }
            });

            it("when not approved nor owner", async () => {
                await erc20Vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address], 
                    [BigNumber.from(10**9)],
                    false,
                    []
                );
                console.log(await erc20Vault.tvl());
                expect(await erc20Vault.tvl()).to.deep.equal([
                    BigNumber.from(10**9),
                    BigNumber.from(0),
                ]);
            });
        });

        describe("collectEarnings", () => {

        });

        describe("reclaimTokens", () => {

        });

        describe("claimRewards", () => {
            
        });

    });
});
