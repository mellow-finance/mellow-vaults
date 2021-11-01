import { expect } from "chai";
import { ethers, network } from "hardhat";
import { ContractFactory, Contract, Signer } from "ethers";
import Exceptions from "./library/Exceptions";
import { BigNumber } from "@ethersproject/bignumber";
import {
    AaveVaultFactory,
    AaveVault,
    AaveVaultManager,
    ERC20,
} from "./library/Types";
import { deployAaveVaultSystem } from "./library/Deployments";
import {
    ProtocolGovernance,
    VaultGovernance,
    VaultGovernanceFactory,
} from "./library/Types";

describe("AaveVaultFactory", function () {
    this.timeout(100 * 1000);

    let deployer: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let user: Signer;
    let protocolGovernanceAdmin: Signer;

    let protocolGovernance: ProtocolGovernance;
    let tokens: ERC20[];
    let AaveVault: AaveVault;
    let AaveVaultManager: AaveVaultManager;
    let AaveVaultFactory: AaveVaultFactory;

    let nft: number;
    let vaultGovernance: VaultGovernance;
    let vaultGovernanceFactory: VaultGovernanceFactory;

    before(async () => {
        [deployer, stranger, treasury, protocolGovernanceAdmin] =
            await ethers.getSigners();
        ({
            AaveVault,
            AaveVaultManager,
            AaveVaultFactory,
            vaultGovernance,
            vaultGovernanceFactory,
            protocolGovernance,
            tokens,
            nft,
        } = await deployAaveVaultSystem({
            protocolGovernanceAdmin: protocolGovernanceAdmin,
            treasury: await treasury.getAddress(),
            tokensCount: 10,
            permissionless: true,
            vaultManagerName: "vault manager",
            vaultManagerSymbol: "Aavevm ¯\\_(ツ)_/¯",
        }));
    });

    describe("constructor", () => {
        it("has correct vaultGovernance address", async () => {
            expect(await AaveVault.vaultGovernance()).to.equal(
                vaultGovernance.address
            );
            console.log(1);
        });

        it("has zero tvl", async () => {
            expect(await AaveVault.tvl()).to.deep.equal([
                BigNumber.from(0),
                BigNumber.from(0),
            ]);
            console.log(2);
        });

        it("has zero earnings", async () => {
            expect(await AaveVault.earnings()).to.deep.equal([
                BigNumber.from(0),
                BigNumber.from(0),
            ]);
            console.log(3);
        });

        it("has correct nft owner", async () => {
            expect(await AaveVaultManager.ownerOf(nft)).to.equals(
                await deployer.getAddress()
            );
            console.log(4);
        });
    });

    describe("push", () => {
        describe("when not approved not owner", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.connect(stranger).push(
                        [tokens[0].address],
                        [BigNumber.from(1)],
                        false,
                        []
                    )
                ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
            });
            console.log(5);
        });

        describe("when tokens and tokenAmounts lengthes do not match", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.push(
                        [tokens[0].address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        true,
                        []
                    )
                ).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
            });
            console.log(6);
        });

        describe("when tokens are not sorted", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.push(
                        [tokens[1].address, tokens[0].address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        true,
                        []
                    )
                ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });
            console.log(7);
        });

        describe("when tokens are not unique", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.push(
                        [tokens[0].address, tokens[0].address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        true,
                        []
                    )
                ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });
            console.log(8);
        });

        describe("when tokens not sorted nor unique", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.push(
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
            console.log(9);
        });

        // FIXME: Should NOT pass when amounts do not match actual balance!
        it("passes when no tokens transferred", async () => {
            const amounts = await AaveVault.callStatic.push(
                [tokens[0].address],
                [BigNumber.from(10 ** 9)],
                true,
                []
            );
            expect(amounts).to.deep.equal([BigNumber.from(10 ** 9)]);
            console.log(10);
        });

        it("passes when tokens transferred", async () => {
            await tokens[1].transfer(
                AaveVault.address,
                BigNumber.from(100 * 10 ** 9)
            );
            const args = [
                [tokens[1].address],
                [BigNumber.from(100 * 10 ** 9)],
                true,
                [],
            ];
            const amounts = await AaveVault.callStatic.push(...args);
            const tx = await AaveVault.push(...args);
            await tx.wait();
            expect(amounts).to.deep.equal([BigNumber.from(100 * 10 ** 9)]);
        });
        console.log(11);
    });

    describe("transferAndPush", () => {
        describe("when not approved nor owner", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.connect(stranger).transferAndPush(
                        await deployer.getAddress(),
                        [tokens[0].address],
                        [BigNumber.from(1)],
                        false,
                        []
                    )
                ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
            });
            console.log(12);
        });

        describe("when tokens and tokenAmounts lengthes do not match", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.transferAndPush(
                        await deployer.getAddress(),
                        [tokens[0].address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        true,
                        []
                    )
                ).to.be.revertedWith(Exceptions.INCONSISTENT_LENGTH);
            });
            console.log(13);
        });

        describe("when tokens are not sorted", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.transferAndPush(
                        await deployer.getAddress(),
                        [tokens[1].address, tokens[0].address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        true,
                        []
                    )
                ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });
            console.log(14);
        });

        describe("when tokens are not unique", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.transferAndPush(
                        await deployer.getAddress(),
                        [tokens[0].address, tokens[0].address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        true,
                        []
                    )
                ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });
            console.log(15);
        });

        describe("when tokens are not sorted nor unique", async () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.transferAndPush(
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
            console.log(16);
        });

        it("passes", async () => {
            expect(
                await AaveVault.callStatic.transferAndPush(
                    await deployer.getAddress(),
                    [tokens[0].address],
                    [BigNumber.from(10 ** 9)],
                    true,
                    []
                )
            ).to.deep.equal([BigNumber.from(10 ** 9)]);
            console.log(17);
        });

        describe("when not enough balance", () => {
            it("reverts", async () => {
                await tokens[0].transfer(
                    await user.getAddress(),
                    BigNumber.from(10 ** 3)
                );
                await tokens[0]
                    .connect(user)
                    .approve(AaveVault.address, BigNumber.from(10 ** 3));
                await expect(
                    AaveVault.transferAndPush(
                        await user.getAddress(),
                        [tokens[0].address],
                        [BigNumber.from(10 ** 9)],
                        true,
                        []
                    )
                ).to.be.revertedWith(Exceptions.ERC20_INSUFFICIENT_BALANCE);
            });
            console.log(18);
        });
    });

    describe("tvl", () => {
        before(async () => {
            for (let i: number = 0; i < tokens.length; ++i) {
                await tokens[i].connect(deployer).approve(
                    AaveVault.address,
                    BigNumber.from(10 ** 9)
                        .mul(BigNumber.from(10 ** 9))
                        .mul(BigNumber.from(10 ** 9))
                );
            }
        });
        console.log(19);
        it("passes", async () => {
            await AaveVault.transferAndPush(
                await deployer.getAddress(),
                [tokens[0].address],
                [BigNumber.from(10 ** 9)],
                false,
                []
            );

            expect(await AaveVault.tvl()).to.deep.equal([
                BigNumber.from(10 ** 9),
                BigNumber.from(0),
            ]);
        });
        console.log(20);
    });

    describe("claimRewards", () => {
        // TODO: test claimRewards
    });

    describe("collectEarnings", () => {
        describe("when called by stranger", async () => {
            it("when called by stranger", async () => {
                await expect(
                    AaveVault.connect(stranger).collectEarnings(
                        AaveVault.address,
                        []
                    )
                ).to.be.revertedWith(Exceptions.APPROVED_OR_OWNER);
            });
            console.log(21);
        });

        describe("when destination is not a contract address", () => {
            it("reverts", async () => {
                await expect(
                    AaveVault.collectEarnings(await deployer.getAddress(), [])
                ).to.be.revertedWith(Exceptions.CONTRACT_REQUIRED);
            });
            console.log(22);
        });

        // TODO: test collectEarnings
    });
});
