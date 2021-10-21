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
    ProtocolGovernance
} from "./library/Types";
import { deployERC20VaultSystem } from "./library/Deployments";
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
            };

            ({
                tokens,
                erc20VaultFactory,
                erc20VaultManager,
                vaultGovernanceFactory,
                vaultGovernance,
                protocolGovernance,
                erc20Vault,
                nft
            } = await deployERC20VaultSystem(options));
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

            it("passes when no tokens transferred", async () => {
                const amounts = await erc20Vault.callStatic.push(
                    [tokens[0].address], 
                    [BigNumber.from(10**9)],
                    true,
                    []
                );
                expect(amounts).to.deep.equal([BigNumber.from(10**9)]);
            });

            it("passes when tokens transferred", async () => {
                await tokens[1].transfer(erc20Vault.address, BigNumber.from(100 * 10**9));
                const args = [
                    [tokens[1].address],
                    [BigNumber.from(100 * 10**9)],
                    true,
                    []
                ];
                const amounts = await erc20Vault.callStatic.push(...args);
                const tx = await erc20Vault.push(...args);
                await tx.wait();
                expect(amounts).to.deep.equal([BigNumber.from(100 * 10**9)]);
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
                        BigNumber.from(10**9).mul(BigNumber.from(10**9)).mul(BigNumber.from(10**9))
                    );
                }
            });

            it("passes", async () => {
                await erc20Vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address], 
                    [BigNumber.from(10**9)],
                    false,
                    []
                );
                console.log((await erc20Vault.tvl()).map((x: BigNumber) => {
                    return x.toString();
                }));
                // .to.deep.equal([
                //     BigNumber.from(10**9),
                //     BigNumber.from(0),
                // ]);
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
