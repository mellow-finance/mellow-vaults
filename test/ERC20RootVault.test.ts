import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep } from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20Vault, ERC20RootVault } from "./types";
import { setupVault, combineVaults } from "../deploy/0000_utils";
import { expect } from "chai";

type CustomContext = {
    erc20Vault: ERC20Vault;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "ERC20RootVault::chargeFees",
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
                    const erc20VaultNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

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
                        [erc20VaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );
                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
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

        describe("#chargeFees", () => {
            it("check that fees has been charged", async () => {
                let firstDepositValue = BigNumber.from(10).pow(18).mul(200);
                let secondDepositValue = firstDepositValue.mul(3);
                await this.subject.deposit([firstDepositValue.mul(2), firstDepositValue], 1);
                await mint(
                    "WETH",
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18).mul(3500)
                );
                await mint(
                    "USDC",
                    this.erc20Vault.address,
                    BigNumber.from(10).pow(18).mul(3500)
                );
                await sleep(86400 * 30);
                await expect(this.subject.deposit([secondDepositValue.mul(2), secondDepositValue.mul(3)], 50)).to.emit(
                    this.subject,
                    "PerformanceFeesCharged"
                );
            });
        });
    }
);
