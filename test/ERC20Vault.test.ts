import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import {
    ERC20,
    ERC20Vault,
    ProtocolGovernance,
    VaultRegistry,
    VaultFactory,
    ERC20VaultGovernance,
    AaveVault,
} from "./library/Types";
import { deployERC20Tokens, deploySubVaultSystem } from "./library/Deployments";
import Exceptions from "./library/Exceptions";

describe("ERC20Vault", function () {
    describe("when permissionless is set to true", () => {
        let deployer: Signer;
        let user: Signer;
        let stranger: Signer;
        let treasury: Signer;
        let protocolGovernanceAdmin: Signer;

        let tokens: ERC20[];
        let ERC20Vault: ERC20Vault;
        let AaveVault: AaveVault;
        let ERC20VaultFactory: VaultFactory;
        let protocolGovernance: ProtocolGovernance;
        let ERC20VaultGovernance: ERC20VaultGovernance;
        let vaultRegistry: VaultRegistry;
        let nftERC20: number;
        let nftAave: number;
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
                });
            });
        });

        beforeEach(async () => {
            ({
                ERC20VaultFactory,
                vaultRegistry,
                protocolGovernance,
                ERC20VaultGovernance,
                tokens,
                ERC20Vault,
                nftERC20,
            } = await deployment());
            // approve all tokens to the ERC20Vault
            for (let i: number = 0; i < tokens.length; ++i) {
                await tokens[i].connect(deployer).approve(
                    ERC20Vault.address,
                    BigNumber.from(10 ** 9)
                        .mul(BigNumber.from(10 ** 9))
                        .mul(BigNumber.from(10 ** 9))
                );
            }
            await vaultRegistry
                .connect(deployer)
                .approve(await protocolGovernanceAdmin.getAddress(), nftERC20);
        });

        describe("constructor", () => {
            it("has correct vaultGovernance address", async () => {
                expect(await ERC20Vault.vaultGovernance()).to.equal(
                    ERC20VaultGovernance.address
                );
            });

            it("has zero tvl", async () => {
                expect(await ERC20Vault.tvl()).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });

            it("has zero earnings", async () => {
                expect(await ERC20Vault.earnings()).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });

            it("has correct nftERC20 owner", async () => {
                expect(await vaultRegistry.ownerOf(nftERC20)).to.equals(
                    await deployer.getAddress()
                );
            });
        });

        describe("push", () => {
            describe("when not approved not owner", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.connect(stranger).push(
                            [tokens[0].address],
                            [BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
                });
            });

            describe("when tokens and tokenAmounts lengthes do not match", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.push(
                            [tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
                });
            });

            describe("when tokens are not sorted", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.push(
                            [tokens[1].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens are not unique", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.push(
                            [tokens[0].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens not sorted nor unique", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.push(
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
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            // FIXME: Should NOT pass when amounts do not match actual balance!
            it("passes when no tokens transferred", async () => {
                const amounts = await ERC20Vault.callStatic.push(
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    []
                );
                expect(amounts).to.deep.equal([BigNumber.from(10 ** 9)]);
            });

            it("passes when tokens transferred", async () => {
                await tokens[1].transfer(
                    ERC20Vault.address,
                    BigNumber.from(100 * 10 ** 9)
                );
                const args = [
                    [tokens[1].address],
                    [BigNumber.from(100 * 10 ** 9)],
                    [],
                ];
                const amounts = await ERC20Vault.callStatic.push(...args);
                const tx = await ERC20Vault.push(...args);
                await tx.wait();
                expect(amounts).to.deep.equal([BigNumber.from(100 * 10 ** 9)]);
            });
        });

        describe("transferAndPush", () => {
            describe("when not approved nor owner", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.connect(stranger).transferAndPush(
                            await deployer.getAddress(),
                            [tokens[0].address],
                            [BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
                });
            });

            describe("when tokens and tokenAmounts lengthes do not match", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.transferAndPush(
                            await deployer.getAddress(),
                            [tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
                });
            });

            describe("when tokens are not sorted", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.transferAndPush(
                            await deployer.getAddress(),
                            [tokens[1].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens are not unique", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.transferAndPush(
                            await deployer.getAddress(),
                            [tokens[0].address, tokens[0].address],
                            [BigNumber.from(1), BigNumber.from(1)],
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            describe("when tokens are not sorted nor unique", async () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.transferAndPush(
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
                            []
                        )
                    ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
                });
            });

            it("passes", async () => {
                expect(
                    await ERC20Vault.callStatic.transferAndPush(
                        await deployer.getAddress(),
                        [tokens[0].address],
                        [BigNumber.from(10 ** 9)],
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
                        .approve(ERC20Vault.address, BigNumber.from(10 ** 3));
                    await expect(
                        ERC20Vault.transferAndPush(
                            await user.getAddress(),
                            [tokens[0].address],
                            [BigNumber.from(10 ** 9)],
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
                        ERC20Vault.address,
                        BigNumber.from(10 ** 9)
                            .mul(BigNumber.from(10 ** 9))
                            .mul(BigNumber.from(10 ** 9))
                    );
                }
            });

            it("passes", async () => {
                await ERC20Vault.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    []
                );

                expect(await ERC20Vault.tvl()).to.deep.equal([
                    BigNumber.from(10 ** 9),
                    BigNumber.from(0),
                ]);
            });
        });

        describe("collectEarnings", () => {
            describe("when called by stranger", async () => {
                it("when called by stranger", async () => {
                    await expect(
                        ERC20Vault.connect(stranger).collectEarnings(
                            ERC20Vault.address,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
                });
            });

            describe("when destination is not a contract address", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.collectEarnings(
                            await deployer.getAddress(),
                            []
                        )
                    ).to.be.revertedWith(Exceptions.VALID_PULL_DESTINATION);
                });
            });
        });

        describe("reclaimTokens", () => {
            let anotherToken: ERC20;

            before(async () => {
                anotherToken = (await deployERC20Tokens(1))[0];
                await anotherToken
                    .connect(deployer)
                    .transfer(ERC20Vault.address, BigNumber.from(10 ** 9));
            });
        });
    });
});
