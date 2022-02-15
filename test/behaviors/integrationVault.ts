import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { TestContext } from "../library/setup";
import Exceptions from "../library/Exceptions";
import {
    mintUniV3Position_USDC_WETH,
    randomAddress,
    withSigner,
} from "../library/Helpers";
import {
    INTEGRATION_VAULT_INTERFACE_ID,
    VAULT_REGISTRY_INTERFACE_ID,
} from "../library/Constants";
import { ERC20RootVault, ERC20Vault } from "../types";
import { ethers } from "hardhat";

export type IntegrationVaultContext<S extends Contract, F> = TestContext<
    S,
    F
> & {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
};

export function integrationVaultBehavior<S extends Contract>(
    this: IntegrationVaultContext<S, {}>,
    {}: {}
) {
    describe("#push", () => {
        it("emits Push event", async () => {
            await expect(
                this.subject.push([this.usdc.address], [BigNumber.from(1)], [])
            ).to.emit(this.subject, "Push");
        });
        it("passes when tokens transferred", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });
            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.subject.address, result.tokenId);
            const args = [
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                [],
            ];
            const amounts = await this.subject.callStatic.push(...args);
            expect(amounts[0]).to.deep.equal(
                BigNumber.from(10).pow(6).mul(3000)
            );
        });

        describe("edge cases", () => {
            it("reverts when vault's nft is 0", async () => {
                await ethers.provider.send("hardhat_setStorageAt", [
                    this.subject.address,
                    "0x4", // address of _nft
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                ]);
                await expect(
                    this.subject.push(
                        [this.usdc.address],
                        [BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INIT);
            });
            xit("reverts when ownerNft is 0", async () => {
                let tokenId = await ethers.provider.send("eth_getStorageAt", [
                    this.subject.address,
                    "0x4",
                ]);
                console.log(tokenId);
                await withSigner(
                    this.erc20RootVault.address,
                    async (signer) => {
                        await this.vaultRegistry
                            .connect(signer)
                            .approve(ethers.constants.AddressZero, tokenId);
                        await this.vaultRegistry
                            .connect(signer)
                            .transferFrom(
                                this.erc20RootVault.address,
                                ethers.constants.AddressZero,
                                tokenId
                            );
                    }
                );
                await expect(
                    this.subject.push(
                        [this.usdc.address],
                        [BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INIT);
            });
            it("reverts when tokens and tokenAmounts lengths do not match", async () => {
                await expect(
                    this.subject.push(
                        [this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVALID_VALUE);
            });
            it("reverts when tokens are not sorted", async () => {
                await expect(
                    this.subject.push(
                        [this.weth.address, this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("reverts when tokens are not unique", async () => {
                await expect(
                    this.subject.push(
                        [this.usdc.address, this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("reverts when tokens not sorted nor unique", async () => {
                await expect(
                    this.subject.push(
                        [
                            this.weth.address,
                            this.usdc.address,
                            this.weth.address,
                        ],
                        [
                            BigNumber.from(1),
                            BigNumber.from(1),
                            BigNumber.from(1),
                        ],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.usdc.transfer(signer.address, BigNumber.from(1));
                    await this.usdc
                        .connect(signer)
                        .approve(this.subject.address, BigNumber.from(1));

                    await expect(
                        this.subject
                            .connect(signer)
                            .push([this.usdc.address], [BigNumber.from(1)], [])
                    ).to.not.be.reverted;
                });
            });
        });
    });

    describe("#transferAndPush", () => {
        it("emits Push event", async () => {
            await expect(
                this.subject.transferAndPush(
                    this.deployer.address,
                    [this.usdc.address],
                    [BigNumber.from(1)],
                    []
                )
            ).to.emit(this.subject, "Push");
        });
        it("passes when tokens transferred", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });
            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.subject.address, result.tokenId);
            const args = [
                this.deployer.address,
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                [],
            ];
            const amounts = await this.subject.callStatic.transferAndPush(
                ...args
            );
            expect(amounts[0]).to.deep.equal(
                BigNumber.from(10).pow(6).mul(3000)
            );
        });
        it("reverts when not enough balance", async () => {
            const deployerBalance = await this.usdc.balanceOf(
                this.deployer.address
            );
            await expect(
                this.subject.transferAndPush(
                    this.deployer.address,
                    [this.usdc.address],
                    [BigNumber.from(deployerBalance).mul(2)],
                    []
                )
            ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
        });

        describe("edge cases", () => {
            it("reverts when vault's nft is 0", async () => {
                await ethers.provider.send("hardhat_setStorageAt", [
                    this.subject.address,
                    "0x4", // address of _nft
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                ]);
                await expect(
                    this.subject.transferAndPush(
                        this.deployer.address,
                        [this.usdc.address],
                        [BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INIT);
            });
            it("reverts when tokens and tokenAmounts lengths do not match", async () => {
                await expect(
                    this.subject.transferAndPush(
                        this.deployer.address,
                        [this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.reverted;
            });
            it("reverts when tokens are not sorted", async () => {
                await expect(
                    this.subject.transferAndPush(
                        this.deployer.address,
                        [this.weth.address, this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("reverts when tokens are not unique", async () => {
                await expect(
                    this.subject.transferAndPush(
                        this.deployer.address,
                        [this.usdc.address, this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("reverts when tokens not sorted nor unique", async () => {
                await expect(
                    this.subject.transferAndPush(
                        this.deployer.address,
                        [
                            this.weth.address,
                            this.usdc.address,
                            this.weth.address,
                        ],
                        [
                            BigNumber.from(1),
                            BigNumber.from(1),
                            BigNumber.from(1),
                        ],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.usdc.transfer(signer.address, BigNumber.from(1));
                    await this.usdc
                        .connect(signer)
                        .approve(this.subject.address, BigNumber.from(1));

                    await expect(
                        this.subject
                            .connect(signer)
                            .transferAndPush(
                                signer.address,
                                [this.usdc.address],
                                [BigNumber.from(1)],
                                []
                            )
                    ).to.not.be.reverted;
                });
            });
        });
    });

    describe("#supportsInterface", () => {
        it(`returns true if this contract supports ${INTEGRATION_VAULT_INTERFACE_ID} interface`, async () => {
            expect(
                await this.subject.supportsInterface(
                    INTEGRATION_VAULT_INTERFACE_ID
                )
            ).to.be.true;
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .supportsInterface(INTEGRATION_VAULT_INTERFACE_ID)
                    ).to.not.be.reverted;
                });
            });
        });

        describe("edge cases:", () => {
            describe("when contract does not support the given interface", () => {
                it("returns false", async () => {
                    expect(
                        await this.subject.supportsInterface(
                            VAULT_REGISTRY_INTERFACE_ID
                        )
                    ).to.be.false;
                });
            });
        });
    });

    describe("#reclaimTokens", () => {
        it("emits ReclaimTokens event", async () => {
            await expect(
                this.subject.reclaimTokens([this.usdc.address])
            ).to.emit(this.subject, "ReclaimTokens");
        });
        it("reclaims successfully", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });
            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.subject.address, result.tokenId);
            const args = [
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                [],
            ];
            await this.subject.push(...args);
            await this.subject.reclaimTokens([
                this.usdc.address,
                this.weth.address,
            ]);
        });

        describe("edge cases:", () => {
            it("reverts when vault's nft is 0", async () => {
                await ethers.provider.send("hardhat_setStorageAt", [
                    this.subject.address,
                    "0x4", // address of _nft
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                ]);
                await expect(
                    this.subject.reclaimTokens([randomAddress()])
                ).to.be.revertedWith(Exceptions.INIT);
            });
            it("reverts when passed never allowed token", async () => {
                await expect(
                    this.subject.reclaimTokens([randomAddress()])
                ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
            });
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .reclaimTokens([this.usdc.address])
                    ).to.not.be.reverted;
                });
            });
        });
    });

    describe("#pull", () => {
        it("emits Pull event", async () => {
            await expect(
                this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [BigNumber.from(1)],
                    []
                )
            ).to.emit(this.subject, "Pull");
        });
        it("pulls tokens", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });
            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.subject.address, result.tokenId);
            const args = [
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                [],
            ];
            await this.subject.push(...args);
            await expect(await this.subject.pull(
                this.erc20Vault.address,
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(3000)],
                []
            )).to.not.be.reverted;
        });

        describe.only("edge cases:", () => {
            it("nothing is pulled when nothing is pushed", async () => {
                const pulledAmounts = await this.subject.callStatic.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [BigNumber.from(10).pow(6).mul(3000)],
                    []
                );
                expect(pulledAmounts[0]).to.equal(BigNumber.from(0));
            });
            it("reverts when vault's nft is 0", async () => {
                await ethers.provider.send("hardhat_setStorageAt", [
                    this.subject.address,
                    "0x4", // address of _nft
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                ]);
                await expect(
                    this.subject.pull(
                        this.deployer.address,
                        [this.usdc.address],
                        [BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INIT);
            });
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .pull(
                                s.address,
                                [this.usdc.address],
                                BigNumber.from(1),
                                []
                            )
                    ).to.not.be.reverted;
                });
            });
        });
    });

    describe("#isValidSignature", () => {
        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .isValidSignature(
                                randomAddress(),
                                INTEGRATION_VAULT_INTERFACE_ID
                            )
                    ).to.not.be.reverted;
                });
            });
        });
    });
}
