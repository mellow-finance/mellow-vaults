import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber, Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
    VaultRegistry,
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
        console.log("deployer", await deployer.getAddress());
        console.log("admin", await admin.getAddress());
        console.log("treasury", await treasury.getAddress());
        console.log("strategy", await strategy.getAddress());
        console.log("stranger", await stranger.getAddress());
        console.log("anotherTreasury", await anotherTreasury.getAddress());
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
            } = await deploySubVaultsXGatewayVaultSystem({
                adminSigner: admin,
                treasury: await treasury.getAddress(),
                vaultOwnerSigner: deployer,
                strategy: await strategy.getAddress(),
            }));
            console.log("gatewayVault", gatewayVault.address);
            console.log(
                "gatewayVaultGovernance",
                gatewayVaultGovernance.address
            );
            console.log("ERC20Vault", ERC20Vault.address);
            console.log("ERC20VaultGovernance", ERC20VaultGovernance.address);
            console.log("protocolGovernance", protocolGovernance.address);
            console.log("nftERC20", nftERC20);
            console.log("anotherNftERC20", anotherNftERC20);
            console.log(
                "tokens",
                tokens.map((token) => token.address)
            );
            console.log("vaultRegistry", vaultRegistry.address);
            for (let i: number = 0; i < tokens.length; ++i) {
                await tokens[i].connect(deployer).approve(
                    gatewayVault.address,
                    BigNumber.from(10 ** 9)
                        .mul(BigNumber.from(10 ** 9))
                        .mul(BigNumber.from(10 ** 9))
                );
            }
            await vaultRegistry.approve(await strategy.getAddress(), 4);
            console.log(
                "vaultRegistry.ownerOf(nftERC20)",
                (await vaultRegistry.ownerOf(nftERC20)).toString()
            );
            console.log(
                "vaultRegistry.ownerOf(anotherNftERC20)",
                (await vaultRegistry.ownerOf(anotherNftERC20)).toString()
            );
            console.log("\n\n=== RUNTIME ===\n\n");
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
                ).to.be.revertedWith("INIT");
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
                ).to.be.revertedWith("L");
            });
        });

        describe("when leftovers happen", () => {
            it("returns them!", async () => {
                const amount = BigNumber.from(10 ** 9);
                expect(BigNumber.from(await tokens[0].balanceOf(await deployer.getAddress())).mod(2)).to.equal(
                    0
                );
                await tokens[0]
                    .connect(deployer)
                    .approve(gatewayVault.address, BigNumber.from(amount.mul(2).add(1)));
                await expect(
                    gatewayVault
                        .connect(deployer)
                        .transferAndPush(await deployer.getAddress(), [tokens[0].address], [amount], [])
                ).to.emit(gatewayVault, "Push");
                await expect(
                    gatewayVault
                        .connect(deployer)
                        .transferAndPush(await deployer.getAddress(), [tokens[0].address], [amount.add(1)], [])
                ).to.emit(gatewayVault, "Push");
                expect(BigNumber.from(await tokens[0].balanceOf(await deployer.getAddress())).mod(2)).to.equal(
                    0
                );
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

    describe("earnings", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty earnings", async () => {
                expect(await gatewayVault.earnings()).to.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
                ]);
            });
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

    describe("vaultEarnings", () => {
        describe("when nothing pushed yet", () => {
            it("returns empty earnings", async () => {
                expect(await gatewayVault.vaultEarnings(0)).to.be.deep.equal([
                    BigNumber.from(0),
                    BigNumber.from(0),
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
                ).to.be.revertedWith("SBIN");
            });
        });

        describe("when passed zero sized list", () => {
            it("reverts", async () => {
                await gatewayVault.setVaultGovernance(
                    await deployer.getAddress()
                );
                await gatewayVault.setSubvaultNfts([]);
                await expect(gatewayVault.addSubvaults([])).to.be.revertedWith(
                    "SBL"
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
                ).to.be.revertedWith("NFT0");
            });
        });
    });
});
