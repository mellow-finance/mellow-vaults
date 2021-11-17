import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
    VaultRegistry,
    AaveVault,
} from "./library/Types";
import Exceptions from "./library/Exceptions";
import { deploySubVaultsXGatewayVaultSystem } from "./library/Deployments";

describe("GatewayVault", () => {
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let strategy: Signer;
    let anotherTreasury: Signer;
    let ERC20VaultGovernance: VaultGovernance;
    let AaveVault: AaveVault;
    let protocolGovernance: ProtocolGovernance;
    let vaultRegistry: VaultRegistry;
    let ERC20Vault: Vault;
    let AnotherERC20Vault: Vault;
    let nftERC20: number;
    let anotherNftERC20: number;
    let tokens: ERC20[];
    let gatewayVault: Vault;
    let gatewayVaultGovernance: VaultGovernance;
    let gatewayNft: number;
    let deployment: Function;

    before(async () => {
        [deployer, admin, stranger, treasury, anotherTreasury, strategy] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({
                gatewayVault,
                gatewayVaultGovernance,
                ERC20VaultGovernance,
                protocolGovernance,
                nftERC20,
                anotherNftERC20,
                tokens,
                ERC20Vault,
                AnotherERC20Vault,
                vaultRegistry,
                AaveVault,
            } = await deploySubVaultsXGatewayVaultSystem({
                adminSigner: admin,
                treasury: await treasury.getAddress(),
                vaultOwnerSigner: deployer,
                strategy: await strategy.getAddress(),
            }));
            for (let i: number = 0; i < tokens.length; ++i) {
                await tokens[i].connect(deployer).approve(
                    gatewayVault.address,
                    BigNumber.from(10 ** 9)
                        .mul(BigNumber.from(10 ** 9))
                        .mul(BigNumber.from(10 ** 9))
                );
            }
            await vaultRegistry.approve(await strategy.getAddress(), 4);
        });
    });

    beforeEach(async () => {
        await deployment();
    });

    describe("vaultTokens", () => {
        it("returns correct ERC20Vault tokens", async () => {
            expect(await ERC20Vault.vaultTokens()).to.deep.equal(
                tokens.map((token) => token.address)
            );
        });
    });

    describe("push", () => {
        it("when called by stranger", async () => {
            await expect(
                gatewayVault
                    .connect(stranger)
                    .push([tokens[0].address], [BigNumber.from(10 ** 9)], [])
            ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
        });

        describe("when not subvaultNfts length is zero", () => {
            it("reverts", async () => {
                await gatewayVault.setSubvaultNfts([]);
                await tokens[0]
                    .connect(deployer)
                    .approve(gatewayVault.address, BigNumber.from(10 ** 10));
                await expect(
                    gatewayVault.push(
                        [tokens[0].address],
                        [BigNumber.from(10 ** 9)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INITIALIZED_ALREADY);
            });
        });

        describe("when trying to push the limits", () => {
            it("reverts", async () => {
                const amount = BigNumber.from(2 * 10 ** 9).mul(
                    BigNumber.from(10 ** 9)
                );
                await tokens[0]
                    .connect(deployer)
                    .transfer(gatewayVault.address, amount);
                await expect(
                    gatewayVault.push([tokens[0].address], [amount], [])
                ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
            });
        });

        describe("when leftovers happen", () => {
            it("returns them!", async () => {
                const amount = BigNumber.from(10 ** 9);
                expect(
                    BigNumber.from(
                        await tokens[0].balanceOf(await deployer.getAddress())
                    ).mod(2)
                ).to.equal(0);
                await tokens[0]
                    .connect(deployer)
                    .approve(
                        gatewayVault.address,
                        BigNumber.from(amount.mul(2).add(1))
                    );
                await expect(
                    gatewayVault
                        .connect(deployer)
                        .transferAndPush(
                            await deployer.getAddress(),
                            [tokens[0].address],
                            [amount],
                            []
                        )
                ).to.emit(gatewayVault, "Push");
                await expect(
                    gatewayVault
                        .connect(deployer)
                        .transferAndPush(
                            await deployer.getAddress(),
                            [tokens[0].address],
                            [amount.add(1)],
                            []
                        )
                ).to.emit(gatewayVault, "Push");
                expect(
                    BigNumber.from(
                        await tokens[0].balanceOf(await deployer.getAddress())
                    ).mod(2)
                ).to.equal(0);
            });
        });

        it("emits Push", async () => {
            await tokens[0]
                .connect(deployer)
                .transfer(gatewayVault.address, BigNumber.from(10 ** 10));
            await expect(
                gatewayVault
                    .connect(deployer)
                    .push([tokens[0].address], [BigNumber.from(10 ** 9)], [])
            ).to.emit(gatewayVault, "Push");
        });
    });

    describe("pull", () => {
        describe("when called by stranger", () => {
            it("reverts", async () => {
                await tokens[0]
                    .connect(deployer)
                    .transfer(gatewayVault.address, BigNumber.from(10 ** 10));
                await gatewayVault
                    .connect(deployer)
                    .push([tokens[0].address], [BigNumber.from(10 ** 9)], []);
                await expect(
                    gatewayVault
                        .connect(stranger)
                        .pull(
                            await deployer.getAddress(),
                            [tokens[0].address],
                            [BigNumber.from(10 ** 9)],
                            []
                        )
                ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
            });
        });
        it("emits Pull", async () => {
            await tokens[0]
                .connect(deployer)
                .transfer(gatewayVault.address, BigNumber.from(10 ** 10));
            await gatewayVault
                .connect(deployer)
                .push([tokens[0].address], [BigNumber.from(10 ** 9)], []);
            expect(
                await gatewayVault
                    .connect(deployer)
                    .pull(
                        await deployer.getAddress(),
                        [tokens[0].address],
                        [BigNumber.from(10 ** 9)],
                        []
                    )
            ).to.emit(gatewayVault, "Pull");
        });
    });

    describe("constructor", () => {
        it("creates GatewayVault", async () => {
            expect(
                await deployer.provider?.getCode(gatewayVault.address)
            ).not.to.be.equal("0x");
        });
    });

    describe("subvaultNfts", () => {
        it("returns nfts", async () => {
            expect(await gatewayVault.subvaultNfts()).to.be.deep.equal([
                nftERC20,
                anotherNftERC20,
            ]);
        });
    });

    describe("tvl", () => {
        it("when nothing yet pushed", async () => {
            expect(await gatewayVault.tvl()).to.deep.equal([
                BigNumber.from(0),
                BigNumber.from(0),
            ]);
        });
    });

    describe("subvaultTvl", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty tvl", async () => {
                expect(await gatewayVault.subvaultTvl(0)).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });
        });
    });

    describe("subvaultsTvl", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty tvl", async () => {
                expect(await gatewayVault.subvaultsTvl()).to.be.deep.equal([
                    [BigNumber.from(0), BigNumber.from(0)],
                    [BigNumber.from(0), BigNumber.from(0)],
                ]);
            });
        });
    });

    describe("hasSubvault", () => {
        describe("when passed actual ERC20Vault", () => {
            it("returns true", async () => {
                expect(await gatewayVault.hasSubvault(ERC20Vault.address)).to.be
                    .true;
                expect(
                    await gatewayVault.hasSubvault(AnotherERC20Vault.address)
                ).to.be.true;
            });
        });

        describe("when passed not subvault", () => {
            it("returns false", async () => {
                expect(
                    await gatewayVault.hasSubvault(await stranger.getAddress())
                ).to.be.false;
            });
        });
    });

    describe("addSubvaults", () => {
        describe("when called not by VaultGovernance", () => {
            it("reverts", async () => {
                await expect(
                    gatewayVault
                        .connect(strategy)
                        .addSubvaults([ERC20Vault.address])
                ).to.be.revertedWith(
                    Exceptions.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE
                );
            });
        });

        describe("when already initialized", () => {
            it("reverts", async () => {
                await gatewayVault.setVaultGovernance(
                    await deployer.getAddress()
                );
                await expect(
                    gatewayVault.addSubvaults([ERC20Vault.address])
                ).to.be.revertedWith(Exceptions.SUB_VAULT_INITIALIZED);
            });
        });

        describe("when passed zero sized list", () => {
            it("reverts", async () => {
                await gatewayVault.setVaultGovernance(
                    await deployer.getAddress()
                );
                await gatewayVault.setSubvaultNfts([]);
                await expect(gatewayVault.addSubvaults([])).to.be.revertedWith(
                    Exceptions.SUB_VAULT_LENGTH
                );
            });
        });

        describe("when passed nfts contains zero", () => {
            it("reverts", async () => {
                await gatewayVault.setVaultGovernance(
                    await deployer.getAddress()
                );
                await gatewayVault.setSubvaultNfts([]);
                await expect(
                    gatewayVault.addSubvaults([ERC20Vault.address, 0])
                ).to.be.revertedWith(Exceptions.NFT_ZERO);
            });
        });
    });

    describe("_isValidPullDestination", () => {
        describe("when passed some contract", () => {
            it("returns false", async () => {
                expect(
                    await gatewayVault.isValidPullDestination(AaveVault.address)
                ).to.be.false;
            });
        });
    });

    describe("_isVaultToken", () => {
        describe("when passed not vault token", () => {
            it("returns false", async () => {
                expect(
                    await gatewayVault.isVaultToken(await stranger.getAddress())
                ).to.be.false;
            });
        });
    });
});
