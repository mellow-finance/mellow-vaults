import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, SqueethVault } from "./types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import {
    INTEGRATION_VAULT_INTERFACE_ID,
    YEARN_VAULT_INTERFACE_ID,
} from "./library/Constants";
import Exceptions from "./library/Exceptions";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<SqueethVault, DeployOptions, CustomContext>("SqueethVault", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { curveRouter } = await getNamedAccounts();
                this.curveRouter = curveRouter;
                this.preparePush = async () => {
                    await sleep(0);
                };

                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let yearnVaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                await setupVault(hre, yearnVaultNft, "YearnVaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, yearnVaultNft],
                    this.deployer.address,
                    this.deployer.address
                );
                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const yearnVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    yearnVaultNft
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
                    "YearnVault",
                    yearnVault
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

    integrationVaultBehavior.call(this, {});
});
