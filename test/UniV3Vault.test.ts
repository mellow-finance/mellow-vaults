import { expect } from "chai";
import { deployments, getNamedAccounts, ethers } from "hardhat";
import { UniV3Vault } from "./types/UniV3Vault";
import { WERC20Test } from "./types/WERC20Test";
import { withSigner, depositW9, sortAddresses } from "./library/Helpers";

describe("UniV3Vault", () => {
    const aaveVaultNft: number = 1;
    const uniV3VaultNft: number = 2;
    const erc20VaultNft: number = 3;
    const gatewayVaultNft: number = 4;
    let deploymentFixture: Function;
    let aaveVault: string;
    let erc20Vault: string;
    let uniV3Vault: string;
    let gatewayVault: string;
    let uniV3VaultGovernance: string;
    let uniV3VaultContract: UniV3Vault;

    before(async () => {
        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            const { read, get } = deployments;
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
            uniV3Vault = await read(
                "VaultRegistry",
                "vaultForNft",
                uniV3VaultNft
            );
            uniV3VaultGovernance = (await get("UniV3VaultGovernance")).address;
            gatewayVault = await read(
                "VaultRegistry",
                "vaultForNft",
                gatewayVaultNft
            );
            uniV3VaultContract = await ethers.getContractAt(
                "UniV3Vault",
                uniV3Vault
            );
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
    });

    describe("#constructor", () => {
        describe("when passed more than 2 tokens", () => {
            it("reverts", async () => {
                const factory = await ethers.getContractFactory("UniV3Vault");
                const { weth, wbtc, usdc } = await getNamedAccounts();
                await expect(
                    factory.deploy(
                        uniV3VaultGovernance,
                        sortAddresses([weth, wbtc, usdc]),
                        3000
                    )
                ).to.be.revertedWith("TL");
            });
        });
    });

    describe("#tvl", () => {
        describe("when has not initial funds", () => {
            it("returns zero tvl", async () => {
                expect(await uniV3VaultContract.tvl()).to.eql([
                    ethers.constants.Zero,
                    ethers.constants.Zero,
                ]);
            });
        });

        describe("when has assets", () => {
            it("returns correct tvl", async () => {});
        });
    });
});
