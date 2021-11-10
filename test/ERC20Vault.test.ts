import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import {
    ERC20,
    ERC20Vault,
    ProtocolGovernance,
    VaultRegistry,
    VaultFactory,
    VaultGovernance,
} from "./library/Types";
import { deployERC20Tokens, deploySubVaultSystem } from "./library/Deployments";
import Exceptions from "./library/Exceptions";

// TODO: Add _isValidPullDestination tests

describe("ERC20Vault", function () {
    describe("when permissionless is set to true", () => {
        let deployer: Signer;
        let user: Signer;
        let stranger: Signer;
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

        before(async () => {
            [deployer, user, stranger, treasury, protocolGovernanceAdmin] =
                await ethers.getSigners();

            deployment = deployments.createFixture(async () => {
                await deployments.fixture();
                return await deploySubVaultSystem({
                    tokensCount: 2,
                    adminSigner: deployer,
                    treasury: await treasury.getAddress(),
                    vaultOwner: await deployer.getAddress(),
                    vaultType: "ERC20Vault",
                });
            });
        });

        beforeEach(async () => {
            ({
                vaultFactory,
                vaultRegistry,
                protocolGovernance,
                vaultGovernance,
                tokens,
                vault,
                nft,
            } = await deployment());
            // approve all tokens to the vault
            for (let i: number = 0; i < tokens.length; ++i) {
                await tokens[i].connect(deployer).approve(
                    vault.address,
                    BigNumber.from(10 ** 9)
                        .mul(BigNumber.from(10 ** 9))
                        .mul(BigNumber.from(10 ** 9))
                );
            }
            await vaultRegistry
                .connect(deployer)
                .approve(await protocolGovernanceAdmin.getAddress(), nft);
        });

        describe("constructor", () => {
            it("has correct vaultGovernance address", async () => {
                expect(await vault.vaultGovernance()).to.equal(
                    vaultGovernance.address
                );
            });

            it("has zero tvl", async () => {
                expect(await vault.tvl()).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });

            it("has zero earnings", async () => {
                expect(await vault.earnings()).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });

            it("has correct nft owner", async () => {
                expect(await vaultRegistry.ownerOf(nft)).to.equals(
                    await deployer.getAddress()
                );
            });
        });

        describe("push", () => {
            describe("when not approved not owner", () => {
                it("reverts", async () => {
                    await expect(
                        vault
                            .connect(stranger)
                            .push(
                                [tokens[0].address],
                                [BigNumber.from(1)],
                                false,
                                []
                            )
                    ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
                });
            });

            describe("when tokens and tokenAmounts lengthes do not match", () => {
                it("reverts", async () => {
                    await expect(
                        vault.push(
                            [tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
                });
            });

            describe("when tokens are not sorted", () => {
                it("reverts", async () => {
                    await expect(
                        vault.push(
                            [tokens[1].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens are not unique", () => {
                it("reverts", async () => {
                    await expect(
                        vault.push(
                            [tokens[0].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens not sorted nor unique", () => {
                it("reverts", async () => {
                    await expect(
                        vault.push(
                            [
                                tokens[1].address,
                                tokens[0].address,
                                tokens[1].address,
                            ],
                            [
                                BigNumber.from(1),
                                BigNumber.from(1),
                                BigNumber.from(1),
                            ],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            // FIXME: Should NOT pass when amounts do not match actual balance!
            it("passes when no tokens transferred", async () => {
                const amounts = await vault.callStatic.push(
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    true,
                    []
                );
                expect(amounts).to.deep.equal([BigNumber.from(10 ** 9)]);
            });

            it("passes when tokens transferred", async () => {
                await tokens[1].transfer(
                    vault.address,
                    BigNumber.from(100 * 10 ** 9)
                );
                const args = [
                    [tokens[1].address],
                    [BigNumber.from(100 * 10 ** 9)],
                    true,
                    [],
                ];
                const amounts = await vault.callStatic.push(...args);
                const tx = await vault.push(...args);
                await tx.wait();
                expect(amounts).to.deep.equal([BigNumber.from(100 * 10 ** 9)]);
            });
        });

        describe("transferAndPush", () => {
            describe("when not approved nor owner", () => {
                it("reverts", async () => {
                    await expect(
                        vault
                            .connect(stranger)
                            .transferAndPush(
                                await deployer.getAddress(),
                                [tokens[0].address],
                                [BigNumber.from(1)],
                                false,
                                []
                            )
                    ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
                });
            });

            describe("when tokens and tokenAmounts lengthes do not match", () => {
                it("reverts", async () => {
                    await expect(
                        vault.transferAndPush(
                            await deployer.getAddress(),
                            [tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
                });
            });

            describe("when tokens are not sorted", () => {
                it("reverts", async () => {
                    await expect(
                        vault.transferAndPush(
                            await deployer.getAddress(),
                            [tokens[1].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens are not unique", () => {
                it("reverts", async () => {
                    await expect(
                        vault.transferAndPush(
                            await deployer.getAddress(),
                            [tokens[0].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens are not sorted nor unique", async () => {
                it("reverts", async () => {
                    await expect(
                        vault.transferAndPush(
                            await deployer.getAddress(),
                            [
                                tokens[1].address,
                                tokens[0].address,
                                tokens[1].address,
                            ],
                            [
                                BigNumber.from(1),
                                BigNumber.from(1),
                                BigNumber.from(1),
                            ],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            it("passes", async () => {
                expect(
                    await vault.callStatic.transferAndPush(
                        await deployer.getAddress(),
                        [tokens[0].address],
                        [BigNumber.from(10 ** 9)],
                        true,
                        []
                    )
                ).to.deep.equal([BigNumber.from(10 ** 9)]);
            });

            describe("when not enough balance", () => {
                it("reverts", async () => {
                    await tokens[0].transfer(
                        await user.getAddress(),
                        BigNumber.from(10 ** 3)
                    );
                    await tokens[0]
                        .connect(user)
                        .approve(vault.address, BigNumber.from(10 ** 3));
                    await expect(
                        vault.transferAndPush(
                            await user.getAddress(),
                            [tokens[0].address],
                            [BigNumber.from(10 ** 9)],
                            true,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.ERC20_INSUFFICIENT_BALANCE);
                });
            });
        });

        describe("tvl", () => {
            before(async () => {
                for (let i: number = 0; i < tokens.length; ++i) {
                    await tokens[i].connect(deployer).approve(
                        vault.address,
                        BigNumber.from(10 ** 9)
                            .mul(BigNumber.from(10 ** 9))
                            .mul(BigNumber.from(10 ** 9))
                    );
                }
            });

            it("passes", async () => {
                await vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    false,
                    []
                );

                expect(await vault.tvl()).to.deep.equal([
                    BigNumber.from(10 ** 9),
                    BigNumber.from(0),
                ]);
            });
        });

        describe("claimRewards", () => {
            // TODO: test claimRewards
        });

        describe("pull", () => {
            // TODO: test pull
        });

        describe("collectEarnings", () => {
            describe("when called by stranger", async () => {
                it("when called by stranger", async () => {
                    await expect(
                        vault
                            .connect(stranger)
                            .collectEarnings(vault.address, [])
                    ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
                });
            });

            describe("when destination is not a contract address", () => {
                it("reverts", async () => {
                    await expect(
                        vault.collectEarnings(await deployer.getAddress(), [])
                    ).to.be.revertedWith(Exceptions.VALID_PULL_DESTINATION);
                });
            });

            // TODO: test collectEarnings
        });

        describe("reclaimTokens", () => {
            let anotherToken: ERC20;

            before(async () => {
                anotherToken = (await deployERC20Tokens(1))[0];
                await anotherToken
                    .connect(deployer)
                    .transfer(vault.address, BigNumber.from(10 ** 9));
            });

            // TODO: test reclaimTokens
        });
    });
});
