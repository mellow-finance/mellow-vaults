import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint } from "./library/Helpers";
import { contract } from "./library/setup";
import { UniV3Vault } from "./types";
import { setupVault } from "../deploy/0000_utils";
import {integrationVaultBehavior} from "./behaviors/integrationVault";

type CustomContext = {};

type DeployOptions = {};

contract<UniV3Vault, DeployOptions, CustomContext>(
    "UniV3Vault",
    function () {
        const uniV3PoolFee = 3000;

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { read } = deployments;

                    const { uniswapV3PositionManager } =
                        await getNamedAccounts();

                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();

                    const uniV3VaultNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                uniV3PoolFee,
                            ],
                        }
                    );

                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3VaultNft
                    )

                    await this.vaultRegistry.approve(uniV3Vault, uniV3VaultNft);
                    await this.vaultRegistry.transferFrom(this.deployer.address, uniV3Vault, uniV3VaultNft);

                    this.subject = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    );

                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        integrationVaultBehavior.call(this, {});
    }
);
