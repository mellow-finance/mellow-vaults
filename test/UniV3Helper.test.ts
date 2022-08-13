import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    makeFirstDeposit,
    mint,
    mintUniV3Position_USDC_WETH,
    mintUniV3Position_WBTC_WETH,
    randomAddress,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    UniV3Vault,
    UniV3Helper,
    IUniswapV3Pool,
    ERC20RootVault,
} from "./types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { UNIV3_VAULT_INTERFACE_ID } from "./library/Constants";
import Exceptions from "./library/Exceptions";
import { TickMath } from "@uniswap/v3-sdk";
import { BigNumberish } from "ethers";
import { bigInt } from "fast-check";

type CustomContext = {
    rootVault: ERC20RootVault;
    uniV3Vault: UniV3Vault;
    pool: IUniswapV3Pool;
};

type DeployOptions = {};

contract<UniV3Helper, DeployOptions, CustomContext>("UniV3Helper", function () {
    const uniV3PoolFee = 3000;

    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                const { read, deploy } = deployments;

                const {
                    uniswapV3PositionManager,
                    curveRouter,
                    uniswapV3Router,
                    deployer,
                } = await getNamedAccounts();

                await deploy("UniV3Helper", {
                    from: deployer,
                    contract: "UniV3Helper",
                    args: [],
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS,
                });

                const { address: helperAddress } = await hre.ethers.getContract(
                    "UniV3Helper"
                );
                this.subject = await ethers.getContractAt(
                    "UniV3Helper",
                    helperAddress
                );

                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();
                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let uniV3VaultNft = startNft;
                let erc20VaultNft = startNft + 1;
                this.erc20RootVaultNft = startNft + 2;
                let uniV3Helper = (await ethers.getContract("UniV3Helper"))
                    .address;
                await setupVault(hre, uniV3VaultNft, "UniV3VaultGovernance", {
                    createVaultArgs: [
                        tokens,
                        this.deployer.address,
                        uniV3PoolFee,
                        uniV3Helper,
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
                    randomAddress()
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
                this.uniV3Vault = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3Vault
                );
                this.rootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

                this.pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    await this.uniV3Vault.pool()
                );

                this.positionManager = await ethers.getContractAt(
                    INonfungiblePositionManager,
                    uniswapV3PositionManager
                );

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#getPositionTokenAmountsByCapitalOfToken0", () => {
        it("test uniV3Helper", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: 204000,
                tickUpper: 210000,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });

            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.uniV3Vault.address, result.tokenId);
            const position = await this.positionManager.functions[
                "positions(uint256)"
            ](result.tokenId);
            const Q96 = BigNumber.from(2).pow(96);
            const tickToSqrtPrice = (tick: number) => {
                return BigNumber.from(
                    TickMath.getSqrtRatioAtTick(tick).toString()
                );
            };
            const tickToPrice = (tick: number) => {
                const sqrtPrice = tickToSqrtPrice(tick);
                return sqrtPrice.pow(2).div(Q96);
            };
            const spotTick = (await this.pool.slot0()).tick;
            await this.subject.getPositionTokenAmountsByCapitalOfToken0(
                tickToSqrtPrice(position.tickLower),
                tickToSqrtPrice(position.tickUpper),
                tickToSqrtPrice(spotTick),
                tickToPrice(spotTick),
                BigNumber.from(10).pow(10)
            );
        });
    });

    describe("#getTickDeviationForTimeSpan", () => {
        it("returns withFail=true if there is no observation in the pool that was not made before secondsAgo", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: 204000,
                tickUpper: 210000,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });

            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.uniV3Vault.address, result.tokenId);
            const spotTick = (await this.pool.slot0()).tick;
            const response = await this.subject.getTickDeviationForTimeSpan(
                spotTick,
                this.pool.address,
                BigNumber.from(2).pow(32).sub(1)
            );
            expect(response.withFail).to.be.true;
        });
    });

    describe("#liquidityToTokenAmounts", () => {
        it("returns correct vaulues for type(uint128).max", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: 204000,
                tickUpper: 210000,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });

            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.uniV3Vault.address, result.tokenId);
            const { deployer, uniswapV3Router, uniswapV3PositionManager } =
                await getNamedAccounts();

            const uint128Max = BigNumber.from(2).pow(128).sub(1);
            const liquidityToTokenAmountsResponse =
                await this.subject.liquidityToTokenAmounts(
                    uint128Max,
                    this.pool.address,
                    result.tokenId,
                    uniswapV3PositionManager
                );
            const tokenAmountsToLiquidityResponse =
                await this.subject.tokenAmountsToLiquidity(
                    liquidityToTokenAmountsResponse,
                    this.pool.address,
                    result.tokenId,
                    uniswapV3PositionManager
                );

            const delta = uint128Max.sub(tokenAmountsToLiquidityResponse);

            expect(delta.gte(0)).to.be.true;
            expect(delta.lte(BigNumber.from(2).pow(32))).to.be.true;
        });
    });
});
