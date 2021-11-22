import { expect } from "chai";
import { deployments, getNamedAccounts, ethers } from "hardhat";
import { AaveVault } from "./types/AaveVault";
import { WERC20Test } from "./types/WERC20Test";
import { withSigner, depositW9 } from "./library/Helpers";

describe("AaveVault", () => {
    const aaveVaultNft: number = 1;
    const erc20VaultNft: number = 2;
    const gatewayVaultNft: number = 4;
    let deploymentFixture: Function;
    let aaveVault: string;
    let erc20Vault: string;
    let gatewayVault: string;
    let aaveVaultContract: AaveVault;

    before(async () => {
        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            const { read } = deployments;
            aaveVault = await read(
                "VaultRegistry",
                "vaultForNft",
                aaveVaultNft
            );
            erc20Vault = await read(
                "VaultRegistry",
                "vaultForNft",
                erc20VaultNft
            );
            gatewayVault = await read(
                "VaultRegistry",
                "vaultForNft",
                gatewayVaultNft
            );
            aaveVaultContract = await ethers.getContractAt(
                "AaveVault",
                aaveVault
            );
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
    });

    describe("#tvl", () => {
        describe("when has not initial funds", () => {
            it("returns zero tvl", async () => {
                expect(await aaveVaultContract.tvl()).to.eql([
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                ]);
            });
        });
    });

    describe("#updateTvls", () => {
        describe("when tvl had not change", () => {
            it("returns the same tvl", async () => {
                await expect(aaveVaultContract.updateTvls()).to.not.be.reverted;
                expect(await aaveVaultContract.tvl()).to.eql([
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                ]);
            });
        });

        describe("when tvl changed by direct token transfer", () => {
            it("tvl remains unchanged before `updateTvls`", async () => {
                await depositW9(aaveVault, ethers.utils.parseEther("1"));
                expect(await aaveVaultContract.tvl()).to.eql([
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                ]);
            });
        });
    });

    describe("#push", () => {
        describe("when pushed zeroes", () => {
            it("pushes", async () => {
                await withSigner(gatewayVault, async (signer) => {
                    const { weth, wbtc } = await getNamedAccounts();
                    const tokens = [weth, wbtc]
                        .map((t) => t.toLowerCase())
                        .sort();
                    await aaveVaultContract
                        .connect(signer)
                        .push(tokens, [0, 0], []);
                });
            });
        });

        describe("when pushed smth", () => {
            beforeEach(async () => {
                await depositW9(aaveVault, ethers.utils.parseEther("10"));
            });

            describe("when called once", () => {
                it("approves deposits to lendingPool and updates tvl", async () => {
                    const amount = ethers.utils.parseEther("1");
                    await withSigner(gatewayVault, async (signer) => {
                        const { weth, wbtc } = await getNamedAccounts();
                        await expect(
                            aaveVaultContract
                                .connect(signer)
                                .push([wbtc, weth], [0, amount], [])
                        ).to.not.be.reverted;
                        expect(await aaveVaultContract.tvl()).to.eql([
                            ethers.constants.Zero,
                            amount,
                        ]);
                    });
                });
            });

            describe("when called twice", () => {
                it("not performs approve the second time", async () => {
                    const amount = ethers.utils.parseEther("1");
                    await withSigner(gatewayVault, async (signer) => {
                        const { weth, wbtc } = await getNamedAccounts();
                        await expect(
                            aaveVaultContract
                                .connect(signer)
                                .push([wbtc, weth], [0, amount], [])
                        ).to.not.be.reverted;
                        await expect(
                            aaveVaultContract
                                .connect(signer)
                                .push([wbtc, weth], [0, amount], [])
                        ).to.not.be.reverted;
                    });
                });
            });
        });
    });

    describe("#pull", () => {
        const w9Amount = ethers.utils.parseEther("10");
        let wethContract: WERC20Test;

        beforeEach(async () => {
            await deployments.fixture();
            await depositW9(aaveVault, w9Amount);
        });

        describe("when nothing is pushed", () => {
            it("nothing is pulled", async () => {
                await withSigner(gatewayVault, async (signer) => {
                    const { weth, wbtc } = await getNamedAccounts();
                    await aaveVaultContract
                        .connect(signer)
                        .pull(erc20Vault, [wbtc, weth], [0, 0], []);
                    expect(await wethContract.balanceOf(erc20Vault)).to.eql(0);
                });
            });
        });

        describe("when pushed smth", () => {
            it("smth pulled", async () => {
                const amount = ethers.utils.parseEther("1");
                await withSigner(gatewayVault, async (signer) => {
                    const { weth, wbtc } = await getNamedAccounts();
                    await expect(
                        aaveVaultContract
                            .connect(signer)
                            .push([wbtc, weth], [0, amount], [])
                    ).to.not.be.reverted;
                    expect(await aaveVaultContract.tvl()).to.eql([
                        ethers.constants.Zero,
                        amount,
                    ]);
                    const tokens = [weth, wbtc]
                        .map((t) => t.toLowerCase())
                        .sort();
                    await aaveVaultContract
                        .connect(signer)
                        .pull(erc20Vault, tokens, [0, amount], []);
                    const wethContract = await ethers.getContractAt(
                        "WERC20Test",
                        weth
                    );
                    expect(await wethContract.balanceOf(erc20Vault)).to.eql(
                        amount
                    );
                });
            });
        });
    });
});
