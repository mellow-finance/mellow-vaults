import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { mint, withSigner } from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { UniV3Vault } from "../types/UniV3Vault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";

async function mintUniV3Position_USDC_WETH(options: {
    tickLower: BigNumberish;
    tickUpper: BigNumberish;
    usdcAmount: BigNumberish;
    wethAmount: BigNumberish;
    fee: 3000 | 500;
}): Promise<any> {
    const { weth, usdc, deployer, uniswapV3PositionManager } =
        await getNamedAccounts();

    const wethContract = await ethers.getContractAt("WETH", weth);
    const usdcContract = await ethers.getContractAt("ERC20Token", usdc);

    const positionManagerContract = await ethers.getContractAt(
        INonfungiblePositionManager,
        uniswapV3PositionManager
    );

    await mint("WETH", deployer, options.wethAmount);
    await mint("USDC", deployer, options.usdcAmount);

    console.log(
        "weth balance",
        (await wethContract.balanceOf(deployer)).toString()
    );
    console.log(
        "usdc balance",
        (await usdcContract.balanceOf(deployer)).toString()
    );

    if (
        (await wethContract.allowance(deployer, uniswapV3PositionManager)).eq(
            BigNumber.from(0)
        )
    ) {
        await wethContract.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
        console.log(
            `approved weth at ${weth} to uniswapV3PositionManager at ${uniswapV3PositionManager}`
        );
    }
    if (
        (await usdcContract.allowance(deployer, uniswapV3PositionManager)).eq(
            BigNumber.from(0)
        )
    ) {
        await usdcContract.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
        console.log(
            `approved usdc at ${usdc} to uniswapV3PositionManager at ${uniswapV3PositionManager}`
        );
    }

    const mintParams = {
        token0: usdc,
        token1: weth,
        fee: options.fee,
        tickLower: options.tickLower,
        tickUpper: options.tickUpper,
        amount0Desired: options.usdcAmount,
        amount1Desired: options.wethAmount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: deployer,
        deadline: ethers.constants.MaxUint256,
    };

    console.log(`minting new uni v3 position for deployer at ${deployer} 
    \n with params ${JSON.stringify(mintParams)}`);

    const result = await positionManagerContract.callStatic.mint(mintParams);
    await positionManagerContract.mint(mintParams);
    return result;
}

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__UniV3_ERC20_rebalance",
    function () {
        const uniV3PoolFee = 3000;

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;
                    const { deployer, weth, usdc } = await getNamedAccounts();

                    const tokens = [weth, usdc]
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
                            createVaultArgs: [tokens, deployer, uniV3PoolFee],
                        }
                    );
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, deployer],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20VaultNft + 1,
                        [erc20VaultNft, uniV3VaultNft],
                        deployer,
                        deployer
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

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#rebalance", () => {
            it("initializes uniV3 vault with position nft", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -60,
                    tickUpper: 60,
                    usdcAmount: 300000000,
                    wethAmount: 100000000,
                });
                console.log(result.tokenId.toString());
            });
        });
    }
);
