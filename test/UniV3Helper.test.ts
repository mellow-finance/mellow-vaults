import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    makeFirstDeposit,
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    UniV3Vault,
    UniV3Helper,
    IUniswapV3Pool,
    ERC20RootVault,
    IIntegrationVault,
} from "./types";
import {
    combineVaults,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { TickMath } from "@uniswap/v3-sdk";
import { MaxUint256 } from "@uniswap/sdk-core";

type CustomContext = {
    rootVault: ERC20RootVault;
    erc20Vault: IIntegrationVault;
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

                const { uniswapV3PositionManager, deployer } =
                    await getNamedAccounts();

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
        const intervals = [
            [-600, 0],
            [600, 1200],
            [-600, 600],
        ];
        intervals.forEach((borders) => {
            it(`test uniV3Helper, borders: ${borders[0]} ${borders[1]}`, async () => {
                await this.rootVault
                    .connect(this.admin)
                    .addDepositorsToAllowlist([this.deployer.address]);
                await mint(
                    "USDC",
                    this.deployer.address,
                    BigNumber.from(10).pow(15)
                );
                await mint(
                    "WETH",
                    this.deployer.address,
                    BigNumber.from(10).pow(15)
                );
                await this.usdc
                    .connect(this.deployer)
                    .approve(
                        this.rootVault.address,
                        ethers.constants.MaxUint256
                    );
                await this.weth
                    .connect(this.deployer)
                    .approve(
                        this.rootVault.address,
                        ethers.constants.MaxUint256
                    );

                await this.rootVault
                    .connect(this.deployer)
                    .deposit(
                        [BigNumber.from(10).pow(6), BigNumber.from(10).pow(11)],
                        0,
                        []
                    );

                var tick = (await this.pool.slot0()).tick;
                tick -= tick % 600;
                const lowerTick = tick + borders[0];
                const upperTick = tick + borders[1];

                const result = await mintUniV3Position_USDC_WETH({
                    fee: 3000,
                    tickLower: lowerTick,
                    tickUpper: upperTick,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );

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
                var spotTick = (await this.pool.slot0()).tick;

                if (position.tickLower >= spotTick) {
                    spotTick = position.tickLower;
                } else if (position.tickUpper <= spotTick) {
                    spotTick = position.tickUpper;
                }
                const { token0Amount, token1Amount } =
                    await this.subject.getPositionTokenAmountsByCapitalOfToken0(
                        tickToSqrtPrice(position.tickLower),
                        tickToSqrtPrice(position.tickUpper),
                        tickToSqrtPrice(spotTick),
                        tickToPrice((await this.pool.slot0()).tick),
                        BigNumber.from(10).pow(10)
                    );

                const usdcAmount = BigNumber.from(10).pow(18);
                const wethAmount = BigNumber.from(10).pow(21).mul(4);

                await mint("USDC", this.deployer.address, usdcAmount);
                await mint("WETH", this.deployer.address, wethAmount);
                await this.rootVault.deposit([usdcAmount, wethAmount], 0, []);
                const getUniV3Tvl = async () => {
                    const liquidity = await this.pool.liquidity();
                    return await this.uniV3Vault.liquidityToTokenAmounts(
                        liquidity
                    );
                };
                const tvlBefore = await getUniV3Tvl();
                await this.erc20Vault.pull(
                    this.uniV3Vault.address,
                    [this.usdc.address, this.weth.address],
                    [token0Amount, token1Amount],
                    []
                );

                const tvlAfter = await getUniV3Tvl();
                const deltaToken0 = tvlAfter[0].sub(tvlBefore[0]);
                const deltaToken1 = tvlAfter[1].sub(tvlBefore[1]);

                const relativeDeltaToken0 = token0Amount.sub(deltaToken0).abs();
                const relativeDeltaToken1 = token1Amount.sub(deltaToken1).abs();

                const borderToken0 = tvlBefore[0].div(1000).add(10000);
                const borderToken1 = tvlBefore[1].div(1000).add(10000);

                expect(relativeDeltaToken0.lte(borderToken0)).to.be.true;
                expect(relativeDeltaToken1.lte(borderToken1)).to.be.true;
            });
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
            const { uniswapV3PositionManager } = await getNamedAccounts();

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
