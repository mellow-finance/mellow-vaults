import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "../test/helpers/curvePoolABI.json";
import { abi as IWETH } from "../test/helpers/wethABI.json";
import { abi as IWSTETH } from "../test/helpers/wstethABI.json";
import { BigNumber } from "@ethersproject/bignumber";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as fs from "fs";
import * as path from "path";
import {
    Context,
    preparePush,
    getUniV3Tick,
    swapTokens,
    getTvl,
    makeSwap,
    stringToPriceX96,
    getStrategyStats,
    checkUniV3Balance,
    getUniV3Price,
    setupVault,
    combineVaults,
    stringToSqrtPriceX96,
    getTick,
    getPool,
    swapOnCowswap,
} from "./helpers/lstrategy";
import { addSigner, withSigner } from "./helpers/sign";
import { mint, sleep } from "./helpers/utils";
import { TickMath } from "@uniswap/v3-sdk";

task("lstrategy-backtest", "run backtest on univ3 vault")
    .addParam(
        "filename",
        "The name of the file with historical data",
        undefined,
        types.string
    )
    .addParam(
        "width",
        "The width of the interval of positions",
        undefined,
        types.int
    )
    .setAction(async ({ filename, width }, hre: HardhatRuntimeEnvironment) => {
        const context = await setup(hre, width);
        await execute(filename, width, hre, context);
    });

let erc20RebalanceCount = 0;
let uniV3RebalanceCount = 0;
let uniV3Gas = BigNumber.from(0);
let erc20UniV3Gas = BigNumber.from(0);

const initialMint = async (hre: HardhatRuntimeEnvironment) => {
    const { getNamedAccounts, ethers } = hre;
    const { deployer, weth, wsteth } = await getNamedAccounts();
    const smallAmount = BigNumber.from(10).pow(13);

    await mint(hre, "WETH", deployer, smallAmount);

    const wethContract = await ethers.getContractAt(IWETH, weth);
    const wstethContract = await ethers.getContractAt(IWSTETH, wsteth);

    const curvePool = await ethers.getContractAt(
        ICurvePool,
        "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022" // address of curve weth-wsteth
    );
    const steth = await ethers.getContractAt(
        "ERC20Token",
        "0xae7ab96520de3a18e5e111b5eaab095312d7fe84"
    );

    await wethContract.approve(curvePool.address, ethers.constants.MaxUint256);
    await steth.approve(wstethContract.address, ethers.constants.MaxUint256);

    await wethContract.withdraw(smallAmount.div(2));
    const options = { value: smallAmount.div(2) };
    await curvePool.exchange(
        0,
        1,
        smallAmount.div(2),
        ethers.constants.Zero,
        options
    );
    await wstethContract.wrap(smallAmount.div(2).mul(99).div(100));
};

const setup = async (hre: HardhatRuntimeEnvironment, width: number) => {
    await initialMint(hre);

    console.log("In setup");
    const uniV3PoolFee = 500;

    const { deployments, ethers, getNamedAccounts, network } = hre;
    const { deploy, read } = deployments;
    await deployments.fixture();

    const {
        admin,
        deployer,
        uniswapV3PositionManager,
        uniswapV3Router,
        weth,
        wsteth,
    } = await getNamedAccounts();
    const swapRouter = await ethers.getContractAt(ISwapRouter, uniswapV3Router);
    const positionManager = await ethers.getContractAt(
        INonfungiblePositionManager,
        uniswapV3PositionManager
    );
    const adminSigned = await addSigner(hre, admin);
    const deployerSigned = await addSigner(hre, deployer);

    const protocolGovernance = await ethers.getContract("ProtocolGovernance");
    const wethContract = await ethers.getContractAt(IWETH, weth);
    const wstethContract = await ethers.getContractAt(IWSTETH, wsteth);

    await wethContract.approve(
        uniswapV3PositionManager,
        ethers.constants.MaxUint256
    );
    await wstethContract.approve(
        uniswapV3PositionManager,
        ethers.constants.MaxUint256
    );

    await protocolGovernance
        .connect(adminSigned)
        .stagePermissionGrants(wsteth, [
            PermissionIdsLibrary.ERC20_VAULT_TOKEN,
        ]);
    await sleep(network, await protocolGovernance.governanceDelay());
    await protocolGovernance
        .connect(adminSigned)
        .commitPermissionGrants(wsteth);

    const tokens = [weth, wsteth].map((t) => t.toLowerCase()).sort();

    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
    let uniV3LowerVaultNft = startNft;
    let uniV3UpperVaultNft = startNft + 1;
    let erc20VaultNft = startNft + 2;
    let uniV3Helper = (await ethers.getContract("UniV3Helper")).address;

    await setupVault(hre, uniV3LowerVaultNft, "UniV3VaultGovernance", {
        createVaultArgs: [
            tokens,
            deployerSigned.address,
            uniV3PoolFee,
            uniV3Helper,
        ],
    });
    await setupVault(hre, uniV3UpperVaultNft, "UniV3VaultGovernance", {
        createVaultArgs: [
            tokens,
            deployerSigned.address,
            uniV3PoolFee,
            uniV3Helper,
        ],
    });
    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployerSigned.address],
    });

    let cowswapDeployParams = await deploy("MockCowswap", {
        from: deployerSigned.address,
        contract: "MockCowswap",
        args: [],
        log: true,
        autoMine: true,
    });

    let strategyHelper = await deploy("LStrategyHelper", {
        from: deployerSigned.address,
        contract: "LStrategyHelper",
        args: [cowswapDeployParams.address],
        log: true,
        autoMine: true,
    });

    const erc20Vault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft
    );
    const uniV3LowerVault = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3LowerVaultNft
    );
    const uniV3UpperVault = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3UpperVaultNft
    );

    let strategyDeployParams = await deploy("LStrategy", {
        from: deployerSigned.address,
        contract: "LStrategy",
        args: [
            uniswapV3PositionManager,
            cowswapDeployParams.address,
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            strategyHelper.address,
            adminSigned.address,
            width,
        ],
        log: true,
        autoMine: true,
    });
    console.log("Lstrategy deployer");

    let wstethValidator = await deploy("ERC20Validator", {
        from: deployerSigned.address,
        contract: "ERC20Validator",
        args: [protocolGovernance.address],
        log: true,
        autoMine: true,
    });

    await combineVaults(
        hre,
        erc20VaultNft + 1,
        [erc20VaultNft, uniV3LowerVaultNft, uniV3UpperVaultNft],
        deployerSigned.address,
        deployerSigned.address
    );

    const erc20RootVault = await read(
        "VaultRegistry",
        "vaultForNft",
        erc20VaultNft + 1
    );

    const erc20RootVaultContract = await ethers.getContractAt(
        "ERC20RootVault",
        erc20RootVault
    );

    await protocolGovernance
        .connect(adminSigned)
        .stageValidator(wsteth, wstethValidator.address);
    await sleep(network, await protocolGovernance.governanceDelay());
    await protocolGovernance.connect(adminSigned).commitValidator(wsteth);

    let cowswapValidatorDeployParams = await deploy("CowswapValidator", {
        from: deployerSigned.address,
        contract: "CowswapValidator",
        args: [protocolGovernance.address],
        log: true,
        autoMine: true,
    });

    const cowswap = await ethers.getContractAt(
        "MockCowswap",
        cowswapDeployParams.address
    );

    await protocolGovernance
        .connect(adminSigned)
        .stageValidator(cowswap.address, cowswapValidatorDeployParams.address);

    await sleep(network, await protocolGovernance.governanceDelay());
    await protocolGovernance
        .connect(adminSigned)
        .commitValidator(cowswap.address);

    const lstrategy = await ethers.getContractAt(
        "LStrategy",
        strategyDeployParams.address
    );

    const curvePool = await ethers.getContractAt(
        ICurvePool,
        "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022" // address of curve weth-wsteth
    );

    const steth = await ethers.getContractAt(
        "ERC20Token",
        "0xae7ab96520de3a18e5e111b5eaab095312d7fe84"
    );

    await mint(
        hre,
        "WETH",
        lstrategy.address,
        BigNumber.from(10).pow(18).mul(1000)
    );
    console.log("Minted lstrategy");
    await mint(
        hre,
        "WETH",
        deployerSigned.address,
        BigNumber.from(10).pow(18).mul(4000)
    );
    console.log("Minted money");
    await wethContract.approve(curvePool.address, ethers.constants.MaxUint256);
    await steth.approve(wstethContract.address, ethers.constants.MaxUint256);
    await wethContract.withdraw(BigNumber.from(10).pow(18).mul(2000));
    const options = { value: BigNumber.from(10).pow(18).mul(2000) };
    console.log("Before exchange");
    await curvePool.exchange(
        0,
        1,
        BigNumber.from(10).pow(18).mul(2000),
        ethers.constants.Zero,
        options
    );
    console.log("After exchange");
    await wstethContract.wrap(BigNumber.from(10).pow(18).mul(1990));
    console.log("After wrap");

    await wstethContract.transfer(
        lstrategy.address,
        BigNumber.from(10).pow(18).mul(3)
    );
    await wethContract.transfer(
        lstrategy.address,
        BigNumber.from(10).pow(18).mul(3)
    );

    let oracleDeployParams = await deploy("MockOracle", {
        from: deployerSigned.address,
        contract: "MockOracle",
        args: [],
        log: true,
        autoMine: true,
    });

    const mockOracle = await ethers.getContractAt(
        "MockOracle",
        oracleDeployParams.address
    );

    const uniV3VaultGovernance = await ethers.getContract(
        "UniV3VaultGovernance"
    );

    await uniV3VaultGovernance.connect(adminSigned).stageDelayedProtocolParams({
        positionManager: uniswapV3PositionManager,
        oracle: oracleDeployParams.address,
    });
    await sleep(network, 86400);
    await uniV3VaultGovernance
        .connect(adminSigned)
        .commitDelayedProtocolParams();

    await lstrategy.connect(adminSigned).updateTradingParams({
        maxSlippageD: BigNumber.from(10).pow(7),
        oracleSafetyMask: 0x20,
        orderDeadline: 86400 * 30,
        oracle: oracleDeployParams.address,
        maxFee0: BigNumber.from(10).pow(9),
        maxFee1: BigNumber.from(10).pow(9),
    });

    await lstrategy.connect(adminSigned).updateRatioParams({
        erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR
        erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
        minErc20UniV3CapitalRatioDeviationD: BigNumber.from(10).pow(7),
        minErc20TokenRatioDeviationD: BigNumber.from(10).pow(8).div(2),
        minUniV3LiquidityRatioDeviationD: BigNumber.from(10).pow(7).div(5),
    });

    await lstrategy.connect(adminSigned).updateOtherParams({
        intervalWidthInTicks: 100,
        minToken0ForOpening: BigNumber.from(10).pow(6),
        minToken1ForOpening: BigNumber.from(10).pow(6),
        secondsBetweenRebalances: BigNumber.from(10).pow(6),
    });

    return {
        protocolGovernance: protocolGovernance,
        swapRouter: swapRouter,
        positionManager: positionManager,
        LStrategy: lstrategy,
        weth: wethContract,
        wsteth: wstethContract,
        admin: adminSigned,
        deployer: deployerSigned,
        mockOracle: mockOracle,
        erc20RootVault: erc20RootVaultContract,
    } as Context;
};

class PermissionIdsLibrary {
    static REGISTER_VAULT: number = 0;
    static CREATE_VAULT: number = 1;
    static ERC20_TRANSFER: number = 2;
    static ERC20_VAULT_TOKEN: number = 3;
    static ERC20_APPROVE: number = 4;
    static ERC20_APPROVE_RESTRICTED: number = 5;
    static ERC20_TRUSTED_STRATEGY: number = 6;
}

const parseFile = (filename: string): [BigNumber[], string[]] => {
    const csvFilePath = path.resolve(__dirname, filename);
    const fileContent = fs.readFileSync(csvFilePath, { encoding: "utf-8" });
    const fileLen = 30048;
    const blockNumberLen = 8;
    const pricePrecision = 29;
    let prices = new Array();
    let blockNumbers = new Array();

    let index = 0;
    for (let i = 0; i < fileLen; ++i) {
        //let blockNumber = fileContent.slice(index, index + blockNumberLen);
        let price = fileContent.slice(
            index + blockNumberLen + 1,
            index + blockNumberLen + pricePrecision + 1
        );
        let block = fileContent.slice(index, index + blockNumberLen);
        prices.push(price);
        blockNumbers.push(BigNumber.from(block));
        index += blockNumberLen + pricePrecision + 2;
    }

    return [blockNumbers, prices];
};

const changePrice = async (currentTick: BigNumber, context: Context) => {
    let sqrtPriceX96 = BigNumber.from(
        TickMath.getSqrtRatioAtTick(currentTick.toNumber()).toString()
    );
    let priceX96 = sqrtPriceX96
        .mul(sqrtPriceX96)
        .div(BigNumber.from(2).pow(96));
    context.mockOracle.updatePrice(priceX96);
};

const mintMockPosition = async (
    hre: HardhatRuntimeEnvironment,
    context: Context
) => {
    const { ethers } = hre;
    const mintParams = {
        token0: context.wsteth.address,
        token1: context.weth.address,
        fee: 500,
        tickLower: -10000,
        tickUpper: 10000,
        amount0Desired: BigNumber.from(10).pow(20).mul(5),
        amount1Desired: BigNumber.from(10).pow(20).mul(5),
        amount0Min: 0,
        amount1Min: 0,
        recipient: context.deployer.address,
        deadline: ethers.constants.MaxUint256,
    };
    //mint a position in pull to provide liquidity for future swaps
    await context.positionManager.mint(mintParams);
};

const buildInitialPositions = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    width: number
) => {
    let tick = await getUniV3Tick(hre, context);
    await changePrice(tick, context);

    let semiPositionRange = width / 2;

    let tickLeftLower =
        tick.div(semiPositionRange).mul(semiPositionRange).toNumber() -
        semiPositionRange;
    let tickLeftUpper = tickLeftLower + 2 * semiPositionRange;

    let tickRightLower = tickLeftLower + semiPositionRange;
    let tickRightUpper = tickLeftUpper + semiPositionRange;

    let lowerVault = await context.LStrategy.lowerVault();
    let upperVault = await context.LStrategy.upperVault();
    await preparePush({
        hre,
        context,
        vault: lowerVault,
        tickLower: tickLeftLower,
        tickUpper: tickLeftUpper,
    });
    await preparePush({
        hre,
        context,
        vault: upperVault,
        tickLower: tickRightLower,
        tickUpper: tickRightUpper,
    });

    let erc20 = await context.LStrategy.erc20Vault();
    for (let token of [context.weth, context.wsteth]) {
        await token.transfer(erc20, BigNumber.from(10).pow(18).mul(10));
    }
};

const makeDesiredPoolPrice = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    tick: BigNumber
) => {
    let pool = await getPool(hre, context);
    let startTry = BigNumber.from(10).pow(17).mul(60);

    let needIncrease = 0; //mock initialization

    while (true) {
        let currentPoolState = await pool.slot0();
        let currentPoolTick = BigNumber.from(currentPoolState.tick);

        if (currentPoolTick.eq(tick)) {
            break;
        }

        if (currentPoolTick.lt(tick)) {
            if (needIncrease == 0) {
                needIncrease = 1;
                startTry = startTry.div(2);
            }
            await swapTokens(
                hre,
                context,
                context.deployer.address,
                context.deployer.address,
                context.weth,
                context.wsteth,
                startTry
            );
        } else {
            if (needIncrease == 1) {
                needIncrease = 0;
                startTry = startTry.div(2);
            }
            await swapTokens(
                hre,
                context,
                context.deployer.address,
                context.deployer.address,
                context.wsteth,
                context.weth,
                startTry
            );
        }
    }
};

const grantPermissions = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    vault: string
) => {
    const { ethers } = hre;
    const vaultRegistry = await ethers.getContract("VaultRegistry");
    let tokenId = await ethers.provider.send("eth_getStorageAt", [
        vault,
        "0x4", // address of _nft
    ]);
    await withSigner(
        hre,
        context.erc20RootVault.address,
        async (erc20RootVaultSigner) => {
            await vaultRegistry
                .connect(erc20RootVaultSigner)
                .approve(context.LStrategy.address, tokenId);
        }
    );
};

const fullPriceUpdate = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    tick: BigNumber
) => {
    await makeDesiredPoolPrice(hre, context, tick);
    await changePrice(tick, context);
};

const assureEquality = (x: BigNumber, y: BigNumber) => {
    let delta = x.sub(y).abs();
    if (x.lt(y)) {
        x = y;
    }

    return delta.mul(100).lt(x);
};

const getCapital = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    priceX96: BigNumber,
    address: string
) => {
    let tvls = await getTvl(hre, address);
    let minTvl = tvls[0];
    let maxTvl = tvls[1];

    return minTvl[0]
        .add(maxTvl[0])
        .div(2)
        .mul(priceX96)
        .div(BigNumber.from(2).pow(96))
        .add(minTvl[1].add(maxTvl[1]).div(2));
};

const ERC20UniRebalance = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    priceX96: BigNumber
) => {
    const { ethers } = hre;

    let i = 0;
    while (true) {
        let capitalErc20 = await getCapital(
            hre,
            context,
            priceX96,
            await context.LStrategy.erc20Vault()
        );
        let capitalLower = await getCapital(
            hre,
            context,
            priceX96,
            await context.LStrategy.lowerVault()
        );
        let capitalUpper = await getCapital(
            hre,
            context,
            priceX96,
            await context.LStrategy.upperVault()
        );

        if (
            assureEquality(capitalErc20.mul(19), capitalLower.add(capitalUpper))
        ) {
            break;
        }

        const tx = await context.LStrategy.connect(
            context.admin
        ).rebalanceERC20UniV3Vaults(
            [ethers.constants.Zero, ethers.constants.Zero],
            [ethers.constants.Zero, ethers.constants.Zero],
            ethers.constants.MaxUint256
        );
        let receipt = await tx.wait();
        erc20UniV3Gas = erc20UniV3Gas.add(receipt.gasUsed);
        erc20RebalanceCount += 1;
        await swapOnCowswap(hre, context);

        await makeSwap(hre, context);
        i += 1;
        if (i >= 20) {
            console.log(
                "More than 20 iterations of rebalanceERC20UniV3Vaults needed!"
            );
            break;
        }
    }

    //  expect(assureEquality(capitalErc20.mul(19), capitalLower.add(capitalUpper))).to.be.true;
};

const makeRebalances = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    priceX96: BigNumber
) => {
    const { ethers } = hre;

    let wasRebalance = false;

    let iter = 0;

    while (!(await checkUniV3Balance(hre, context))) {
        wasRebalance = true;
        let tx = await context.LStrategy.connect(
            context.admin
        ).rebalanceUniV3Vaults(
            [ethers.constants.Zero, ethers.constants.Zero],
            [ethers.constants.Zero, ethers.constants.Zero],
            ethers.constants.MaxUint256
        );
        let receipt = await tx.wait();
        uniV3Gas = uniV3Gas.add(receipt.gasUsed);
        uniV3RebalanceCount += 1;
        tx = await context.LStrategy.connect(
            context.admin
        ).rebalanceERC20UniV3Vaults(
            [ethers.constants.Zero, ethers.constants.Zero],
            [ethers.constants.Zero, ethers.constants.Zero],
            ethers.constants.MaxUint256
        );
        receipt = await tx.wait();
        erc20UniV3Gas = erc20UniV3Gas.add(receipt.gasUsed);
        erc20RebalanceCount += 1;
        await swapOnCowswap(hre, context);
        iter += 1;
        if (iter >= 20) {
            console.log(
                "More than 20 iterations of rebalance needed needed!!!"
            );
            break;
        }
    }

    if (wasRebalance) await ERC20UniRebalance(hre, context, priceX96);
};

const reportStats = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    fname: string,
    keys: string[]
) => {
    const stats = await getStrategyStats(hre, context);
    for (let i = 0; i < keys.length; ++i) {
        fs.writeFileSync(fname, stats[keys[i] as keyof object], { flag: "a+" });
        if (i + 1 == keys.length) {
            fs.writeFileSync(fname, "\n", { flag: "a+" });
        } else {
            fs.writeFileSync(fname, ",", { flag: "a+" });
        }
    }
};

const execute = async (
    filename: string,
    width: number,
    hre: HardhatRuntimeEnvironment,
    context: Context
) => {
    console.log("Process started");

    await mintMockPosition(hre, context);

    let [blocks, prices] = parseFile(filename);

    console.log("Before price update");

    await fullPriceUpdate(
        hre,
        context,
        getTick(stringToSqrtPriceX96(prices[0]))
    );
    console.log("After price update");
    console.log("Price is: ", (await getUniV3Price(hre, context)).toString());
    await buildInitialPositions(hre, context, width);
    const lowerVault = await context.LStrategy.lowerVault();
    const upperVault = await context.LStrategy.upperVault();
    const erc20vault = await context.LStrategy.erc20Vault();
    await grantPermissions(hre, context, lowerVault);
    await grantPermissions(hre, context, upperVault);
    await grantPermissions(hre, context, erc20vault);

    await ERC20UniRebalance(hre, context, stringToPriceX96(prices[0]));

    const keys = [
        "erc20token0",
        "erc20token1",
        "lowerToken0",
        "lowerToken1",
        "lowerLeftTick",
        "lowerRightTick",
        "upperToken0",
        "upperToken1",
        "upperLeftTick",
        "upperRightTick",
        "currentPrice",
        "currentTick",
        "totalToken0",
        "totalToken1",
    ];

    for (let i = 0; i < keys.length; ++i) {
        if (i == 0) {
            fs.writeFileSync("output.csv", keys[i], { flag: "w" });
        } else {
            fs.writeFileSync("output.csv", keys[i], { flag: "a+" });
        }
        if (i + 1 == keys.length) {
            fs.writeFileSync("output.csv", "\n", { flag: "a+" });
        } else {
            fs.writeFileSync("output.csv", ",", { flag: "a+" });
        }
    }

    console.log(process.memoryUsage());
    let prev = Date.now();
    console.log("length: ", prices.length);
    let prev_block = BigNumber.from(0);
    for (let i = 1; i < prices.length; ++i) {
        if (blocks[i].sub(prev_block).gte((24 * 60 * 60) / 15)) {
            await makeRebalances(hre, context, stringToPriceX96(prices[i]));
            prev_block = blocks[i];
        }
        if (i % 500 == 0) {
            let now = Date.now();
            console.log("Iteration: ", i);
            console.log("Duration: ", now - prev);
            console.log("ERC20Rebalances: ", erc20RebalanceCount);
            console.log("UniV3 rebalances: ", uniV3RebalanceCount);
            console.log("UniV3 used: ", uniV3Gas.toString());
            console.log("ERC20UniV3 used: ", erc20UniV3Gas.toString());
            prev = now;
        }
        await reportStats(hre, context, "output.csv", keys);
        await fullPriceUpdate(
            hre,
            context,
            getTick(stringToSqrtPriceX96(prices[i]))
        );
    }
    console.log("ERC20Rebalances: ", erc20RebalanceCount);
    console.log("UniV3 rebalances: ", uniV3RebalanceCount);
    console.log("UniV3 used: ", uniV3Gas.toString());
    console.log("ERC20UniV3 used: ", erc20UniV3Gas.toString());
};
