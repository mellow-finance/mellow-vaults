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
    GatewayVault,
    GatewayVaultGovernance,
    VaultGovernance,
} from "./library/Types";
import {
    deployERC20Tokens,
    deploySubVaultsXGatewayVaultSystem,
    deploySubVaultSystem,
} from "./library/Deployments";
import Exceptions from "./library/Exceptions";
import { sleep } from "./library/Helpers";
import { values } from "ramda";

describe("Vault", () => {
    let deployer: Signer;
    let user: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let protocolGovernanceAdmin: Signer;
    let strategy: Signer;

    let token: ERC20;
    let differentERC20Token: ERC20;
    let ERC20Vault: ERC20Vault;
    let AnotherERC20Vault: ERC20Vault;
    let anotherERC20Token: ERC20;
    let AaveVault: ERC20Vault;
    let nftERC20: number;
    let nftAave: number;
    let gatewayVault: GatewayVault;
    let vaultRegistry: VaultRegistry;
    let gatewayNft: number;
    let gatewayVaultGovernance: GatewayVaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let differentERC20Vault: ERC20Vault;
    let ERC20VaultGovernance: VaultGovernance;

    before(async () => {
        [
            deployer,
            user,
            stranger,
            treasury,
            protocolGovernanceAdmin,
            strategy,
        ] = await ethers.getSigners();

        ({
            ERC20Vault,
            AnotherERC20Vault,
            AaveVault,
            vaultRegistry,
            nftERC20,
            nftAave,
            gatewayVault,
            gatewayNft,
            gatewayVaultGovernance,
            protocolGovernance,
            ERC20VaultGovernance,
        } = await deploySubVaultsXGatewayVaultSystem({
            adminSigner: protocolGovernanceAdmin,
            vaultOwnerSigner: deployer,
            strategy: await strategy.getAddress(),
            treasury: await deployer.getAddress(),
            enableUniV3Vault: false,
        }));

        ({ ERC20Vault: differentERC20Vault } = await deploySubVaultSystem({
            tokensCount: 2,
            adminSigner: protocolGovernanceAdmin,
            vaultOwner: await deployer.getAddress(),
            treasury: await deployer.getAddress(),
        }));
        token = (await deployERC20Tokens(1))[0];
        anotherERC20Token = (await deployERC20Tokens(1))[0];
        await token
            .connect(deployer)
            .transfer(ERC20Vault.address, BigNumber.from(10 ** 9));
        await vaultRegistry
            .connect(strategy)
            .approve(await user.getAddress(), BigNumber.from(nftERC20));
    });
    describe("reclaimTokens", () => {
        describe("when called by protocolGovernanceAdmin", () => {
            it("reclaims tokens and emits ReclaimTokens event", async () => {
                await expect(
                    ERC20Vault.connect(protocolGovernanceAdmin).reclaimTokens(
                        AaveVault.address,
                        [token.address]
                    )
                ).to.emit(ERC20Vault, "ReclaimTokens");
            });
        });

        describe("when called by stranger", () => {
            it("reverts", async () => {
                await expect(
                    ERC20Vault.connect(stranger).reclaimTokens(
                        AaveVault.address,
                        [token.address]
                    )
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when to is not a contract address", () => {
            it("reverts", async () => {
                await expect(
                    gatewayVault
                        .connect(deployer)
                        .reclaimTokens(await stranger.getAddress(), [
                            token.address,
                        ])
                ).to.be.revertedWith(Exceptions.VALID_PULL_DESTINATION);
            });
        });

        describe("when contract is not approved by vaultRegistry", () => {
            it("reverts", async () => {
                let anotherERC20Vault: ERC20Vault;
                let factory = await ethers.getContractFactory("ERC20Vault");
                anotherERC20Vault = await factory.deploy(
                    gatewayVaultGovernance.address,
                    []
                );
                await anotherERC20Token
                    .connect(deployer)
                    .transfer(
                        anotherERC20Vault.address,
                        BigNumber.from(10 ** 9)
                    );
                await expect(
                    anotherERC20Vault
                        .connect(deployer)
                        .reclaimTokens(anotherERC20Vault.address, [
                            token.address,
                        ])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when called by approved address", () => {
            it("reclaims tokens and emits ReclaimTokens event", async () => {
                await expect(
                    ERC20Vault.connect(protocolGovernanceAdmin).reclaimTokens(
                        AaveVault.address,
                        [token.address]
                    )
                ).to.emit(ERC20Vault, "ReclaimTokens");
            });
        });

        describe("when called by approved user", () => {
            describe("when valid pull destination", () => {
                it("reclaims tokens and emits ReclaimTokens event", async () => {
                    await expect(
                        ERC20Vault.connect(user).reclaimTokens(
                            AnotherERC20Vault.address,
                            [token.address]
                        )
                    ).to.emit(ERC20Vault, "ReclaimTokens");
                });
            });
            describe("when not valid pull destination", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.connect(user).reclaimTokens(
                            await stranger.getAddress(),
                            [token.address]
                        )
                    ).to.be.revertedWith("INTRA");
                });
            });
            describe("when from Vault and to Vault do not belong to one gateway vault", () => {
                it("reverts", async () => {
                    await ERC20Vault.connect(user).reclaimTokens(
                        AnotherERC20Vault.address,
                        [token.address]
                    );
                });
            });
            describe("when from and to Vaults belong to different Gateway Vaults", () => {
                it("reverts", async () => {
                    await expect(
                        ERC20Vault.connect(user).reclaimTokens(
                            differentERC20Vault.address,
                            [differentERC20Vault.address]
                        )
                    ).to.be.revertedWith(Exceptions.VALID_PULL_DESTINATION);
                });
            });
            describe("when from Vault is not registered", () => {
                it("reverts", async () => {
                    let factory = await ethers.getContractFactory("VaultTest");
                    let contract = await factory.deploy(
                        ERC20VaultGovernance.address,
                        []
                    );
                    expect(
                        await contract.isValidPullDestination(
                            ERC20Vault.address
                        )
                    ).to.be.equal(false);
                });
            });
        });
    });

    describe("claimRewards", () => {
        describe("when called by stranger", () => {
            it("reverts", async () => {
                await expect(
                    gatewayVault
                        .connect(stranger)
                        .claimRewards(ERC20Vault.address, [])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
        describe("when not allowed to claim", () => {
            it("reverts", async () => {
                await expect(
                    gatewayVault
                        .connect(deployer)
                        .claimRewards(AaveVault.address, [])
                ).to.be.revertedWith(Exceptions.ALLOWED_TO_CLAIM);
            });
        });
        describe("when allowed to claim and data is empty", () => {
            it("reverts", async () => {
                await protocolGovernance
                    .connect(protocolGovernanceAdmin)
                    .setPendingClaimAllowlistAdd([AaveVault.address]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(protocolGovernanceAdmin)
                    .commitClaimAllowlistAdd();
                await expect(
                    ERC20Vault.connect(user).claimRewards(AaveVault.address, [])
                ).to.be.reverted;
            });
        });
        describe("when allowed to claim and data is not empty", () => {
            it("passes", async () => {
                await protocolGovernance
                    .connect(protocolGovernanceAdmin)
                    .setPendingClaimAllowlistAdd([AaveVault.address]);
                await sleep(Number(await protocolGovernance.governanceDelay()));
                await protocolGovernance
                    .connect(protocolGovernanceAdmin)
                    .commitClaimAllowlistAdd();
                await expect(
                    ERC20Vault.connect(user).claimRewards(AaveVault.address, [])
                ).to.be.reverted;
            });
        });
    });

    describe("pull", () => {
        describe("when called by approved address and pull destination is invalid", () => {
            it("reverts", async () => {
                await expect(
                    ERC20Vault.connect(user).pull(
                        await stranger.getAddress(),
                        [],
                        [],
                        []
                    )
                ).to.be.revertedWith(Exceptions.VALID_PULL_DESTINATION);
            });
        });
    });
});
