import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, mintUniV3Position_USDC_WETH } from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, UniV3Vault } from "./types";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<UniV3Vault, DeployOptions, CustomContext>("UniV3Vault", function () {
    const uniV3PoolFee = 3000;

    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { uniswapV3PositionManager, curveRouter } =
                    await getNamedAccounts();
                this.curveRouter = curveRouter;

                this.positionManager = await ethers.getContractAt(
                    INonfungiblePositionManager,
                    uniswapV3PositionManager
                );

                this.preparePush = async () => {
                    const result = await mintUniV3Position_USDC_WETH({
                        fee: 3000,
                        tickLower: -887220,
                        tickUpper: 887220,
                        usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                        wethAmount: BigNumber.from(10).pow(18),
                    });
                    await this.positionManager.functions[
                        "safeTransferFrom(address,address,uint256)"
                    ](
                        this.deployer.address,
                        this.subject.address,
                        result.tokenId
                    );
                };

                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let uniV3VaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                await setupVault(hre, uniV3VaultNft, "UniV3VaultGovernance", {
                    createVaultArgs: [
                        tokens,
                        this.deployer.address,
                        uniV3PoolFee,
                    ],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, uniV3VaultNft],
                    this.deployer.address,
                    this.deployer.address
                );
                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const uniV3Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    uniV3VaultNft
                );
                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.subject = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3Vault
                );

                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

                for (let address of [
                    this.deployer.address,
                    this.subject.address,
                    this.erc20Vault.address,
                ]) {
                    await mint(
                        "USDC",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await mint(
                        "WETH",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await this.weth.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                }

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#collectEarnings", () => {
        it("emits CollectedEarnings event", async () => {
            await expect(this.subject.collectEarnings()).to.emit(
                this.subject,
                "CollectedEarnings"
            );
        });

        describe("access control:", () => {
            it("allowed: all addresses", async () => {
                await expect(this.subject.collectEarnings()).to.not.be.reverted;
            });
        });
    });

    integrationVaultBehavior.call(this, {});
});
