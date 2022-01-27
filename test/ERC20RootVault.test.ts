import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { mint, sleep, mintUniV3Position_USDC_WETH } from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20Vault, ERC20RootVault, UniV3Vault } from "./types";
import { setupVault, combineVaults } from "../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";

type CustomContext = {
    erc20Vault: ERC20Vault;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "ERC20RootVault::chargefees",
    function () {
        const uniV3PoolFee = 3000;

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    const { uniswapV3PositionManager } =
                        await getNamedAccounts();

                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let uniV3VaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
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
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

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

                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );
                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );
                    this.uniV3Vault = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    );
                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    // add depositor
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    // configure unit prices
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "stageUnitPrice(address,uint256)",
                        this.weth.address,
                        BigNumber.from(10).pow(18)
                    );
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "stageUnitPrice(address,uint256)",
                        this.usdc.address,
                        BigNumber.from(10).pow(18)
                    );
                    await sleep(86400);
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "commitUnitPrice(address)",
                        this.weth.address
                    );
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "commitUnitPrice(address)",
                        this.usdc.address
                    );

                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18)
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

        describe.only("#roflan", () => {
            it("initializes uniV3 vault with position nft", async () => {
                await this.subject.deposit([321], 312);
            });
        });
    }
);
