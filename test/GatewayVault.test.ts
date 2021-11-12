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
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let strategy: Signer;
    let anotherTreasury: Signer;
    let ERC20VaultGovernance: VaultGovernance;
    let AaveVaultGovernance: VaultGovernance;
    let UniV3VaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vaultRegistry: VaultRegistry;
    let ERC20Vault: Vault;
    let UniV3Vault: Vault;
    let AaveVault: Vault;
    let nftERC20: number;
    let nftAave: number;
    let nftUniV3: number;
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
                AaveVaultGovernance,
                UniV3VaultGovernance,
                protocolGovernance,
                nftERC20,
                nftAave,
                nftUniV3,
                tokens,
                ERC20Vault,
                AaveVault,
                UniV3Vault,
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
            console.log("nftAave", nftAave);
            console.log("nftUniV3", nftUniV3);
            console.log(
                "tokens",
                tokens.map((token) => token.address)
            );
            console.log("AaveVault", AaveVault.address);
            console.log("AaveVaultGovernance", AaveVaultGovernance.address);
            console.log("UniV3Vault", UniV3Vault.address);
            console.log("UniV3VaultGovernance", UniV3VaultGovernance.address);
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
                "vaultRegistry.ownerOf(nftAave)",
                (await vaultRegistry.ownerOf(nftAave)).toString()
            );
            console.log(
                "vaultRegistry.ownerOf(nftUniV3)",
                (await vaultRegistry.ownerOf(nftUniV3)).toString()
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
                ERC20Vault.connect(stranger).push(
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    false,
                    []
                )
            ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
        });

        xit("emits Push event", async () => {
            // await tokens[0].connect(deployer).transfer(gatewayVault.address, BigNumber.from(10 ** 9));
            await tokens[0]
                .connect(deployer)
                .transfer(ERC20Vault.address, BigNumber.from(10 ** 9));
            // await tokens[0].connect(deployer).transfer(AaveVault.address, BigNumber.from(10 ** 9));
            await expect(
                ERC20Vault.connect(strategy).push(
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    false,
                    []
                )
            ).to.emit(ERC20Vault, "Push");
            // await tokens[0].connect(deployer).approve(gatewayVault.address, BigNumber.from(10 ** 9));
            // await ERC20Vault.connect(strategy).transferAndPush(
            //     await deployer.getAddress(),
            //     [tokens[0].address],
            //     [BigNumber.from(10 ** 9)],
            //     false,
            //     []
            // );

            console.log((await ERC20Vault.tvl()).toString());
        });
    });

    describe("pull", () => {
        xit("test", async () => {
            await tokens[0]
                .connect(deployer)
                .transfer(ERC20Vault.address, BigNumber.from(10 ** 9));
            await tokens[1]
                .connect(deployer)
                .transfer(AaveVault.address, BigNumber.from(2 * 10 ** 9));
            // await tokens[0].connect(deployer).transfer(AaveVault.address, BigNumber.from(10 ** 9));
            await expect(
                ERC20Vault.connect(strategy).push(
                    [tokens[0].address, tokens[1].address],
                    [BigNumber.from(10 ** 9), BigNumber.from(2 * 10 ** 9)],
                    false,
                    []
                )
            ).to.emit(ERC20Vault, "Push");
            await ERC20Vault.connect(strategy).pull(
                AaveVault.address,
                [tokens[0].address],
                [BigNumber.from(10 ** 9)],
                false,
                []
            );
            // await ERC20Vault
            //     .connect(strategy)
            //     .pull(
            //         AaveVault.address,
            //         [tokens[0].address],
            //         [BigNumber.from(10 ** 9)],
            //         false,
            //         []
            //     );
            console.log((await ERC20Vault.tvl()).toString());
            console.log((await AaveVault.tvl()).toString());
        });

        it("anotherTest", async () => {
            await tokens[0]
                .connect(deployer)
                .transfer(ERC20Vault.address, BigNumber.from(10 ** 9));
            await tokens[1]
                .connect(deployer)
                .transfer(ERC20Vault.address, BigNumber.from(2 * 10 ** 9));
            // await tokens[0].connect(deployer).transfer(AaveVault.address, BigNumber.from(10 ** 9));

            // await expect(
            //     ERC20Vault
            //         .connect(strategy)
            //         .push(
            //             [tokens[0].address],
            //             [BigNumber.from(10 ** 9)],
            //             false,
            //             []
            //         )
            // ).to.emit(ERC20Vault, "Push");

            // await expect(
            //     AaveVault
            //         .connect(strategy)
            //         .push(
            //             [tokens[1].address],
            //             [BigNumber.from(2 * 10 ** 9)],
            //             false,
            //             []
            //         )
            // ).to.emit(ERC20Vault, "Push");

            console.log("ERC20Vault tvl", (await ERC20Vault.tvl()).toString());
            console.log("AaveVault tvl", (await AaveVault.tvl()).toString());
            console.log(
                "gatewayVault subvaults tvls",
                (await gatewayVault.subvaultsTvl()).toString()
            );

            await expect(
                gatewayVault
                    .connect(strategy)
                    .push(
                        [tokens[0].address, tokens[1].address],
                        [BigNumber.from(10 ** 9), BigNumber.from(2 * 10 ** 9)],
                        false,
                        []
                    )
            ).to.emit(gatewayVault, "Push");

            console.log("ERC20Vault tvl", (await ERC20Vault.tvl()).toString());
            console.log("AaveVault tvl", (await AaveVault.tvl()).toString());
            console.log(
                "gatewayVault subvaults tvls",
                (await gatewayVault.subvaultsTvl()).toString()
            );

            await gatewayVault
                .connect(deployer)
                .pull(
                    AaveVault.address,
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    false,
                    []
                );

            console.log("ERC20Vault tvl", (await ERC20Vault.tvl()).toString());
            console.log("AaveVault tvl", (await AaveVault.tvl()).toString());
            console.log(
                "gatewayVault subvaults tvls",
                (await gatewayVault.subvaultsTvl()).toString()
            );
            expect(await ERC20Vault.tvl()).to.deep.equal([
                BigNumber.from(0),
                BigNumber.from(2 * 10 ** 9),
            ]);
            expect(await gatewayVault.tvl()).to.deep.equal([
                BigNumber.from(10 ** 9),
                BigNumber.from(2 * 10 ** 9),
            ]);
            console.log("earnings", (await ERC20Vault.earnings()).toString());
            await gatewayVault
                .connect(deployer)
                .collectEarnings(AaveVault.address, []);
            // await ERC20Vault
            //     .connect(strategy)
            //     .pull(
            //         AaveVault.address,
            //         [tokens[0].address],
            //         [BigNumber.from(10 ** 9)],
            //         false,
            //         []
            //     );
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
                nftAave,
                nftUniV3,
            ]);
        });
    });

    describe("tvl", () => {
        it("when nothing yet pushed", async () => {
            expect(await ERC20Vault.tvl()).to.deep.equal([
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
                expect(await gatewayVault.hasSubvault(AaveVault.address)).to.be
                    .true;
            });
        });

        describe("when passed not ERC20Vault", () => {
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
                ///
            });
        });

        describe("when passed nfts contains zero", () => {});
    });
});
