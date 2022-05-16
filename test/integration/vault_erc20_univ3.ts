import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    sleep,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    addSigner,
    now,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { UniV3Vault } from "../types/UniV3Vault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";

import {
    ERC20RootVaultGovernance,
    IUniswapV3Pool,
    IVaultRegistry,
    ISwapRouter as SwapRouterInterface,
} from "../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { TickMath } from "@uniswap/v3-sdk";
import Common from "../library/Common";
import { randomBytes, randomInt } from "crypto";
import { assert } from "console";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
    positionManager: Contract;
    swapRouter: SwapRouterInterface;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__erc20_univ3",
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

                    const { uniswapV3Router } = await getNamedAccounts();
                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );
                    await this.usdc.approve(
                        this.swapRouter.address,
                        ethers.constants.MaxUint256
                    );
                    await this.weth.approve(
                        this.swapRouter.address,
                        ethers.constants.MaxUint256
                    );

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("rebalance", () => {
            it("initializes uniV3 vault with position nft and increases tvl respectivly", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
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
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result.tokenId
                );
                const uniV3Tvl = await this.uniV3Vault.tvl();
                expect(uniV3Tvl).to.not.contain(0);
                expect(await this.erc20Vault.tvl()).to.deep.equals([
                    [BigNumber.from(0), BigNumber.from(0)],
                    [BigNumber.from(0), BigNumber.from(0)],
                ]);
            });

            it("deposits", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
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
                await this.subject.deposit(
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    0,
                    []
                );
                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from("1000000000000000000"));
            });

            it("pulls univ3 to erc20 and collects earnings", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
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
                await this.subject.deposit(
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    0,
                    []
                );
                await this.uniV3Vault.collectEarnings();
                await this.uniV3Vault.pull(
                    this.erc20Vault.address,
                    [this.usdc.address, this.weth.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    []
                );
            });

            it("replaces univ3 position", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });

                const { deployer, weth, usdc } = await getNamedAccounts();
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](deployer, this.uniV3Vault.address, result.tokenId);
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result.tokenId
                );
                await this.uniV3Vault.pull(
                    this.erc20Vault.address,
                    [usdc, weth],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    []
                );
                const result2 = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](deployer, this.uniV3Vault.address, result2.tokenId);
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result2.tokenId
                );
            });

            const setZeroFeesFixture = deployments.createFixture(async () => {
                await this.deploymentFixture();
                let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                    await ethers.getContract("ERC20RootVaultGovernance");

                let erc20VaultNft = await this.subject.nft();

                await erc20RootVaultGovernance
                    .connect(this.admin)
                    .stageDelayedStrategyParams(erc20VaultNft, {
                        strategyTreasury: randomAddress(),
                        strategyPerformanceTreasury: randomAddress(),
                        privateVault: true,
                        managementFee: BigNumber.from(0),
                        performanceFee: BigNumber.from(0),
                        depositCallbackAddress: ethers.constants.AddressZero,
                        withdrawCallbackAddress: ethers.constants.AddressZero,
                    });
                await sleep(this.governanceDelay);

                await this.erc20RootVaultGovernance
                    .connect(this.admin)
                    .commitDelayedStrategyParams(erc20VaultNft);

                const { protocolTreasury } = await getNamedAccounts();
                await this.protocolGovernance.connect(this.admin).stageParams({
                    forceAllowMask: ALLOW_MASK,
                    maxTokensPerVault: 10,
                    governanceDelay: 86400,
                    protocolTreasury,
                    withdrawLimit: BigNumber.from(10).pow(20),
                });
                await sleep(this.governanceDelay);
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitParams();
            });

            const setApprovedSignerForNft = async (
                nft: BigNumber,
                signer: SignerWithAddress
            ) => {
                let internalParams =
                    await this.erc20VaultGovernance.internalParams();
                let registry: IVaultRegistry = await ethers.getContractAt(
                    "IVaultRegistry",
                    internalParams.registry
                );

                await registry
                    .connect(this.admin)
                    .adminApprove(signer.address, nft);
            };

            const addLiquidity = async (
                signer: SignerWithAddress,
                usdcAmount: BigNumber,
                wethAmount: BigNumber
            ) => {
                await mint("USDC", signer.address, usdcAmount);
                await mint("WETH", signer.address, wethAmount);

                await this.subject
                    .connect(signer)
                    .deposit([usdcAmount, wethAmount], BigNumber.from(0), []);
                await setApprovedSignerForNft(
                    await this.erc20Vault.nft(),
                    signer
                );

                await this.erc20Vault
                    .connect(signer)
                    .pull(
                        this.uniV3Vault.address,
                        [this.usdc.address, this.weth.address],
                        [usdcAmount, wethAmount],
                        []
                    );
            };

            const getLiquidityForAmount0 = (
                sqrtRatioAX96: BigNumber,
                sqrtRatioBX96: BigNumber,
                amount0: BigNumber
            ) => {
                if (sqrtRatioAX96.gt(sqrtRatioBX96)) {
                    var tmp = sqrtRatioAX96;
                    sqrtRatioAX96 = sqrtRatioBX96;
                    sqrtRatioBX96 = tmp;
                }
                var intermediate = sqrtRatioAX96
                    .mul(sqrtRatioBX96)
                    .div(Common.Q96);
                return amount0
                    .mul(intermediate)
                    .div(sqrtRatioBX96.sub(sqrtRatioAX96));
            };

            const getLiquidityForAmount1 = (
                sqrtRatioAX96: BigNumber,
                sqrtRatioBX96: BigNumber,
                amount1: BigNumber
            ) => {
                if (sqrtRatioAX96.gt(sqrtRatioBX96)) {
                    var tmp = sqrtRatioAX96;
                    sqrtRatioAX96 = sqrtRatioBX96;
                    sqrtRatioBX96 = tmp;
                }
                return amount1
                    .mul(Common.Q96)
                    .div(sqrtRatioBX96.sub(sqrtRatioAX96));
            };

            const getSqrtPriceX96 = async () => {
                const poolAddress = await this.uniV3Vault.pool();
                const pool: IUniswapV3Pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    poolAddress
                );
                return (await pool.slot0()).sqrtPriceX96;
            };

            const getLiquidityByTokenAmounts = async (
                amount0: BigNumber,
                amount1: BigNumber
            ) => {
                const { tickLower, tickUpper } =
                    await this.positionManager.positions(
                        await this.uniV3Vault.nft()
                    );
                var sqrtRatioX96 = await getSqrtPriceX96();
                var sqrtRatioAX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(tickLower).toString(10)
                );
                var sqrtRatioBX96 = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(tickUpper).toString(10)
                );

                if (sqrtRatioAX96.gt(sqrtRatioBX96)) {
                    var tmp = sqrtRatioAX96;
                    sqrtRatioAX96 = sqrtRatioBX96;
                    sqrtRatioBX96 = tmp;
                }
                var liquidity = BigNumber.from(0);
                if (sqrtRatioX96.lte(sqrtRatioAX96)) {
                    liquidity = getLiquidityForAmount0(
                        sqrtRatioAX96,
                        sqrtRatioBX96,
                        amount0
                    );
                } else if (sqrtRatioX96 < sqrtRatioBX96) {
                    const liquidity0 = getLiquidityForAmount0(
                        sqrtRatioX96,
                        sqrtRatioBX96,
                        amount0
                    );
                    const liquidity1 = getLiquidityForAmount1(
                        sqrtRatioAX96,
                        sqrtRatioX96,
                        amount1
                    );

                    liquidity =
                        liquidity0 < liquidity1 ? liquidity0 : liquidity1;
                } else {
                    liquidity = getLiquidityForAmount1(
                        sqrtRatioAX96,
                        sqrtRatioBX96,
                        amount1
                    );
                }
                return liquidity;
            };

            const getLiquidity = async (
                signer: SignerWithAddress,
                usdcAmount: BigNumber,
                wethAmount: BigNumber
            ) => {
                await setApprovedSignerForNft(
                    await this.uniV3Vault.nft(),
                    signer
                );

                await this.uniV3Vault
                    .connect(signer)
                    .pull(
                        this.erc20Vault.address,
                        [this.usdc.address, this.weth.address],
                        [usdcAmount, wethAmount],
                        []
                    );

                const usdcBalanceBefore = await this.usdc
                    .connect(this.admin)
                    .balanceOf(signer.address);
                const wethBalanceBefore = await this.weth
                    .connect(this.admin)
                    .balanceOf(signer.address);

                await this.subject.connect(signer).withdraw(
                    signer.address,
                    ethers.constants.MaxUint256, // take all liquidity, that user has
                    [BigNumber.from(0), BigNumber.from(0)],
                    [[], []]
                );

                const usdcBalanceAfter = await this.usdc
                    .connect(this.admin)
                    .balanceOf(signer.address);
                const wethBalanceAfter = await this.weth
                    .connect(this.admin)
                    .balanceOf(signer.address);

                return {
                    usdc: usdcBalanceAfter.sub(usdcBalanceBefore),
                    weth: wethBalanceAfter.sub(wethBalanceBefore),
                };
            };

            const generateRandomBignumber = (limit: BigNumber) => {
                assert(limit.gt(0), "Bignumber underflow");
                const bytes =
                    "0x" + randomBytes(limit._hex.length * 2).toString("hex");
                const result = BigNumber.from(bytes).mod(limit);
                return result;
            };

            const generateArraySplit = (
                w: BigNumber,
                n: number,
                from: BigNumber
            ) => {
                assert(n >= 0, "Zero length array");
                var result: BigNumber[] = [];
                if (w.lt(from.mul(n))) {
                    throw "Weight underflow";
                }

                for (var i = 0; i < n; i++) {
                    result.push(BigNumber.from(from));
                    w = w.sub(from);
                }

                var splits: BigNumber[] = [BigNumber.from(0)];
                for (var i = 0; i < n - 1; i++) {
                    splits.push(generateRandomBignumber(w.add(1)));
                }

                splits = splits.sort((x, y) => {
                    return x.lt(y) ? -1 : 1;
                });

                var deltas: BigNumber[] = [];
                for (var i = 0; i < n - 1; i++) {
                    deltas.push(splits[i + 1].sub(splits[i]));
                    w = w.sub(deltas[i]);
                }
                deltas.push(w);

                for (var i = 0; i < n; i++) {
                    result[i] = result[i].add(deltas[i]);
                }
                return result;
            };

            const push = async (
                delta: BigNumber,
                from: string,
                to: string,
                tokenName: string
            ) => {
                const n = 20;
                const amounts = generateArraySplit(
                    delta,
                    n,
                    BigNumber.from(10).pow(6)
                );
                await mint(tokenName, this.deployer.address, delta);
                for (var i = 0; i < n; i++) {
                    await this.swapRouter.exactInputSingle({
                        tokenIn: from,
                        tokenOut: to,
                        fee: uniV3PoolFee,
                        recipient: this.deployer.address,
                        deadline: ethers.constants.MaxUint256,
                        amountIn: amounts[i],
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0,
                    });
                }
            };

            const pushPriceDown = async (delta: BigNumber) => {
                await push(delta, this.usdc.address, this.weth.address, "USDC");
            };

            const pushPriceUp = async (delta: BigNumber) => {
                await push(delta, this.weth.address, this.usdc.address, "WETH");
            };

            const pushPriceTo = async (price: BigNumber) => {
                var flag = price.lt(await getSqrtPriceX96());
                for (var power = 30; power >= 0; power--) {
                    if (flag) {
                        while (flag) {
                            await pushPriceDown(BigNumber.from(10).pow(power));
                            const currentPrice = await getSqrtPriceX96();
                            flag = price.lt(currentPrice);
                            console.log(
                                `Positive; power: ${power}; price: ${currentPrice.toString()}.`
                            );
                        }
                    } else {
                        while (!flag) {
                            await pushPriceUp(BigNumber.from(10).pow(power));
                            const currentPrice = await getSqrtPriceX96();
                            flag = price.lt(currentPrice);
                            console.log(
                                `Negative; power: ${power}; price: ${currentPrice.toString()}.`
                            );
                        }
                    }

                    if (price.eq(await getSqrtPriceX96())) {
                        break;
                    }
                }
            };

            it.only("multiple deposits for different depositors", async () => {
                await setZeroFeesFixture();
                const numberOfDepositors = 10;
                var depositors: SignerWithAddress[] = [];
                var deposited: BigNumber[][] = [];

                for (var i = 0; i < numberOfDepositors; i++) {
                    depositors.push(await addSigner(randomAddress()));
                    deposited.push([BigNumber.from(0), BigNumber.from(0)]);
                    for (var address of [
                        this.subject.address,
                        this.uniV3Vault.address,
                        this.erc20Vault.address,
                    ]) {
                        await this.weth
                            .connect(depositors[i])
                            .approve(address, ethers.constants.MaxUint256);
                        await this.usdc
                            .connect(depositors[i])
                            .approve(address, ethers.constants.MaxUint256);
                    }
                }

                await this.subject
                    .connect(this.admin)
                    .addDepositorsToAllowlist(depositors.map((x) => x.address));

                const initialUsdcAmount = BigNumber.from(10).pow(6).mul(3000);
                const initialWethAmount = BigNumber.from(10).pow(18);

                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: initialUsdcAmount,
                    wethAmount: initialWethAmount,
                });

                const { deployer } = await getNamedAccounts();
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](deployer, this.uniV3Vault.address, result.tokenId);

                const firstDepositorAmountUsdc = initialUsdcAmount;
                const firstDepositorAmountWeth = initialWethAmount;

                // remove all remaining liqidity
                // for (var i = 0; i < depositors.length; i++) {
                //     await getLiquidity(depositors[i], BigNumber.from(0), BigNumber.from(0));
                // }

                await addLiquidity(
                    depositors[0],
                    firstDepositorAmountUsdc,
                    firstDepositorAmountWeth
                );
                // deposited[0][0] = deposited[0][0].add(fir)

                // const start = now();

                // for (var iteration = 0; iteration < 100; iteration++) {
                //     console.log("Iteration:", iteration, (now() - start));
                //     // pick random signer
                //     var signerIndex = randomInt(depositors.length - 2) + 1;
                //     var signer = depositors[signerIndex];
                    
                //     // [20, 99]
                //     var depositRatio = randomInt(80) + 20;
                //     const usdcDeposit = firstDepositorAmountUsdc.mul(depositRatio).div(100);
                //     const wethDeposit = firstDepositorAmountUsdc.mul(depositRatio).div(100);
                //     await addLiquidity(signer, usdcDeposit, wethDeposit);
                // }
                // console.log("Deposits finished")

                // console.log("Make withdraws")
                // for (var i = 1; i < depositors.length; i++) {
                //     await getLiquidity(depositors[i], BigNumber.from(0), BigNumber.from(0));
                // }
                // console.log("Withdraws finished")

                const {usdc, weth} = await getLiquidity(
                    depositors[0],
                    BigNumber.from(0),
                    BigNumber.from(0)
                );

                console.log(firstDepositorAmountUsdc.toString(), firstDepositorAmountWeth.toString());
                console.log(usdc.toString(), weth.toString());
            });
        });
    }
);
