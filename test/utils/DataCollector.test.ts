import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { contract } from "../library/setup";
import { expect } from "chai";
import { CommonTest, DataCollector, ERC20Token } from "../types";
import Exceptions from "../library/Exceptions";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    mintUniV3Position_WBTC_WETH,
    sleep,
} from "../library/Helpers";
import { BigNumber, BigNumberish } from "ethers";
import {
    combineVaults,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "../../deploy/0000_utils";
import { VaultRequestStruct } from "../types/DataCollector";
import { VaultRegistry } from "../library/Types";
import { IERC20RootVault } from "../types/IERC20RootVault";
import { request } from "http";
import { IIntegrationVault } from "../types/IIntegrationVault";
import { INonfungiblePositionManager } from "../types/INonfungiblePositionManager";

type CustomContext = {
    vaultRegistry: VaultRegistry;
    positionManager: INonfungiblePositionManager;
};
type DeployOptions = {};

contract<DataCollector, DeployOptions, CustomContext>(
    "DataCollector",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { deployments, getNamedAccounts } = hre;
                    const { deploy } = deployments;
                    const { deployer, usdc, uniswapV3PositionManager } =
                        await getNamedAccounts();

                    this.positionManager = await ethers.getContractAt(
                        "INonfungiblePositionManager",
                        uniswapV3PositionManager
                    );

                    await deploy("UniV3Helper", {
                        from: deployer,
                        args: [],
                        log: true,
                        autoMine: true,
                    });
                    await deploy("HStrategyHelper", {
                        from: this.deployer.address,
                        contract: "HStrategyHelper",
                        args: [],
                        log: true,
                        autoMine: true,
                        ...TRANSACTION_GAS_LIMITS,
                    });

                    const uniV3Helper = await ethers.getContract("UniV3Helper");
                    this.vaultRegistry = await ethers.getContract(
                        "VaultRegistry"
                    );
                    await deploy("DataCollector", {
                        from: deployer,
                        args: [
                            usdc,
                            uniswapV3PositionManager,
                            this.vaultRegistry.address,
                            uniV3Helper.address,
                        ],
                        log: true,
                        autoMine: true,
                    });

                    this.subject = await ethers.getContract("DataCollector");
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#constructor", () => {
            it("creates new DataCollector", async () => {
                expect(this.subject.address).not.to.be.eq(
                    ethers.constants.AddressZero
                );
            });
        });

        const getSymbol = (tokenAddress: string) => {
            if (tokenAddress == this.usdc.address) {
                return "USDC";
            } else if (tokenAddress == this.weth.address) {
                return "WETH";
            } else {
                return "WBTC";
            }
        };

        const makeInitialDeposit = async (
            nft: BigNumberish,
            coef: BigNumberish
        ) => {
            const vaultAddress = await this.vaultRegistry.vaultForNft(nft);
            const rootVault: IERC20RootVault = await ethers.getContractAt(
                "ERC20RootVault",
                vaultAddress
            );
            await rootVault
                .connect(this.admin)
                .addDepositorsToAllowlist([this.deployer.address]);
            const tokens = await rootVault.vaultTokens();
            const pullExistentials = await rootVault.pullExistentials();

            let amountsForDeposit: BigNumber[] = [];
            for (var tokenAddress of tokens) {
                const amount = pullExistentials[amountsForDeposit.length]
                    .pow(2)
                    .mul(coef);
                amountsForDeposit.push(amount);
                await mint(
                    getSymbol(tokenAddress),
                    this.deployer.address,
                    amount
                );
                const token: ERC20Token = await ethers.getContractAt(
                    "ERC20Token",
                    tokenAddress
                );
                await token
                    .connect(this.deployer)
                    .approve(rootVault.address, amount);
            }

            await rootVault
                .connect(this.deployer)
                .deposit(amountsForDeposit, 0, []);
        };

        const getIntegrationVault = async (nft: BigNumberish) => {
            const vaultAddress = await this.vaultRegistry.vaultForNft(nft);
            const vault: IIntegrationVault = await ethers.getContractAt(
                "IntegrationVault",
                vaultAddress
            );
            return vault;
        };

        describe("#collect", () => {
            it("collects data for all given vaults in each root vault system", async () => {
                const { deployments, getNamedAccounts } = hre;
                const { read } = deployments;
                const { usdc, weth, wbtc } = await getNamedAccounts();

                var requests: VaultRequestStruct[] = [];
                {
                    const tokens = [usdc, weth]
                        .map((x) => x.toLocaleLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let erc20RootVaultNft = startNft + 2;
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
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
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );
                    await makeInitialDeposit(erc20RootVaultNft, 1);
                    await makeInitialDeposit(erc20RootVaultNft, 10);
                    requests.push({
                        erc20VaultNfts: [erc20VaultNft],
                        moneyVaultNfts: [yearnVaultNft],
                        uniV3VaultNfts: [],
                        fee: 500,
                        rootVaultNft: erc20RootVaultNft,
                        user: this.deployer.address,
                        domainPositionNft: 0,
                    } as VaultRequestStruct);
                }
                {
                    const tokens = [usdc, wbtc]
                        .map((x) => x.toLocaleLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let uniV3VaultNft = startNft + 2;
                    let erc20RootVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
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

                    const { address: uniV3Helper } = await ethers.getContract(
                        "UniV3Helper"
                    );

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                500,
                                uniV3Helper,
                            ],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft, uniV3VaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    await makeInitialDeposit(erc20RootVaultNft, 1);
                    await makeInitialDeposit(erc20RootVaultNft, 10);
                    requests.push({
                        erc20VaultNfts: [erc20VaultNft],
                        moneyVaultNfts: [yearnVaultNft],
                        uniV3VaultNfts: [uniV3VaultNft],
                        fee: 500,
                        rootVaultNft: erc20RootVaultNft,
                        user: this.deployer.address,
                        domainPositionNft: 0,
                    } as VaultRequestStruct);
                }
                {
                    const tokens = [weth, wbtc]
                        .map((x) => x.toLocaleLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let uniV3VaultNft = startNft + 2;
                    let erc20RootVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
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

                    const { address: uniV3Helper } = await ethers.getContract(
                        "UniV3Helper"
                    );

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                500,
                                uniV3Helper,
                            ],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft, uniV3VaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    await makeInitialDeposit(erc20RootVaultNft, 1);
                    await makeInitialDeposit(erc20RootVaultNft, 100);
                    requests.push({
                        erc20VaultNfts: [erc20VaultNft],
                        moneyVaultNfts: [yearnVaultNft],
                        uniV3VaultNfts: [uniV3VaultNft],
                        fee: 500,
                        rootVaultNft: erc20RootVaultNft,
                        user: this.deployer.address,
                        domainPositionNft: 0,
                    } as VaultRequestStruct);
                }
                {
                    const tokens = [usdc, weth]
                        .map((x) => x.toLocaleLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let erc20RootVaultNft = startNft + 2;
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
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
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );
                    await makeInitialDeposit(erc20RootVaultNft, 1);
                    await makeInitialDeposit(erc20RootVaultNft, 10);

                    const from = await getIntegrationVault(erc20VaultNft);
                    const to = await getIntegrationVault(yearnVaultNft);

                    await from
                        .connect(this.deployer)
                        .pull(
                            to.address,
                            tokens,
                            await from.pullExistentials(),
                            []
                        );

                    requests.push({
                        erc20VaultNfts: [erc20VaultNft],
                        moneyVaultNfts: [yearnVaultNft],
                        uniV3VaultNfts: [],
                        fee: 500,
                        rootVaultNft: erc20RootVaultNft,
                        user: this.deployer.address,
                        domainPositionNft: 0,
                    } as VaultRequestStruct);
                }
                {
                    const uniswapFees = 500;
                    const tokens = [weth, wbtc]
                        .map((x) => x.toLocaleLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let uniV3VaultNft = startNft + 2;
                    let erc20RootVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
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

                    const { address: uniV3Helper } = await ethers.getContract(
                        "UniV3Helper"
                    );

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                500,
                                uniV3Helper,
                            ],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft, uniV3VaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    await makeInitialDeposit(erc20RootVaultNft, 1);
                    await makeInitialDeposit(erc20RootVaultNft, 2);

                    const erc20Vault = await getIntegrationVault(erc20VaultNft);
                    const moneyVault = await getIntegrationVault(yearnVaultNft);
                    const uniV3Vault = await getIntegrationVault(uniV3VaultNft);

                    const pullExistentials =
                        await erc20Vault.pullExistentials();
                    await erc20Vault
                        .connect(this.deployer)
                        .pull(moneyVault.address, tokens, pullExistentials, []);

                    const result = await mintUniV3Position_WBTC_WETH({
                        tickLower: 252000,
                        tickUpper: 261600,
                        wbtcAmount: pullExistentials[0],
                        wethAmount: pullExistentials[1],
                        fee: uniswapFees,
                    });
                    await this.positionManager
                        .connect(this.deployer)
                        ["safeTransferFrom(address,address,uint256)"](
                            this.deployer.address,
                            uniV3Vault.address,
                            result.tokenId
                        );
                    await erc20Vault
                        .connect(this.deployer)
                        .pull(uniV3Vault.address, tokens, pullExistentials, []);

                    requests.push({
                        erc20VaultNfts: [erc20VaultNft],
                        moneyVaultNfts: [yearnVaultNft],
                        uniV3VaultNfts: [uniV3VaultNft],
                        fee: uniswapFees,
                        rootVaultNft: erc20RootVaultNft,
                        user: this.deployer.address,
                        domainPositionNft: result.tokenId,
                    } as VaultRequestStruct);
                }
                {
                    const uniswapFees = 500;
                    const tokens = [weth, usdc]
                        .map((x) => x.toLocaleLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;
                    let yearnVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    let uniV3VaultNft = startNft + 2;
                    let erc20RootVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
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

                    const { address: uniV3Helper } = await ethers.getContract(
                        "UniV3Helper"
                    );

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                uniswapFees,
                                uniV3Helper,
                            ],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft, uniV3VaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    await makeInitialDeposit(erc20RootVaultNft, 1);
                    await makeInitialDeposit(erc20RootVaultNft, 25);

                    const erc20Vault = await getIntegrationVault(erc20VaultNft);
                    const moneyVault = await getIntegrationVault(yearnVaultNft);
                    const uniV3Vault = await getIntegrationVault(uniV3VaultNft);

                    const pullExistentials =
                        await erc20Vault.pullExistentials();
                    await erc20Vault
                        .connect(this.deployer)
                        .pull(moneyVault.address, tokens, pullExistentials, []);

                    const { tokenId } = await mintUniV3Position_USDC_WETH({
                        tickLower: 190800,
                        tickUpper: 219600,
                        usdcAmount: pullExistentials[0],
                        wethAmount: pullExistentials[1],
                        fee: uniswapFees,
                    });

                    await this.positionManager
                        .connect(this.deployer)
                        ["safeTransferFrom(address,address,uint256)"](
                            this.deployer.address,
                            uniV3Vault.address,
                            tokenId
                        );
                    await erc20Vault
                        .connect(this.deployer)
                        .pull(uniV3Vault.address, tokens, pullExistentials, []);

                    requests.push({
                        erc20VaultNfts: [erc20VaultNft],
                        moneyVaultNfts: [yearnVaultNft],
                        uniV3VaultNfts: [uniV3VaultNft],
                        fee: uniswapFees,
                        rootVaultNft: erc20RootVaultNft,
                        user: this.deployer.address,
                        domainPositionNft: tokenId,
                    } as VaultRequestStruct);
                }

                const datas = await this.subject.collect(requests);
                for (var data of datas) {
                    console.log(
                        "pricesToUsdcX96:",
                        data.pricesToUsdcX96.toString()
                    );
                    console.log(
                        "tokenLimits:",
                        data.tokenLpLimit._hex,
                        data.tokenLpLimitPerUser._hex
                    );
                    console.log(
                        "user lp balance:",
                        data.userLpBalance.toString()
                    );
                    console.log("total supply:", data.totalSupply.toString());
                    console.log("Erc20 tvls:", data.erc20VaultTvls.toString());
                    console.log("Money tvls:", data.moneyVaultTvls.toString());
                    console.log("UniV3 tvls:", data.uniV3VaultTvls.toString());
                    console.log(
                        "UniV3 spot tvls:",
                        data.uniV3VaultSpotTvls.toString()
                    );
                    console.log(
                        "RootVault tvls:",
                        data.rootVaultTvl.toString()
                    );
                    console.log(
                        "RootVault spot tvls:",
                        data.rootVaultSpotTvl.toString()
                    );
                    console.log(
                        "Domain Position tvl:",
                        data.domainPositionSpotTvl.toString()
                    );
                    console.log();
                }
            });
        });
    }
);
