import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "../test/helpers/curvePoolABI.json";
import { abi as IWETH } from "../test/helpers/wethABI.json";
import { abi as IWSTETH } from "../test/helpers/wstethABI.json";
import { BigNumber } from "@ethersproject/bignumber";
import { task, types } from "hardhat/config";
import { BigNumberish } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { TickMath } from "@uniswap/v3-sdk";
import {
    equals,
} from "ramda";
import * as fs from "fs";
import * as path from "path";
import { Context, preparePush, getUniV3Tick, swapTokens, getTvl, makeSwap, getTick, stringToPriceX96, stringToSqrtPriceX96, getPool, getStrategyStats, checkUniV3Balance, swapOnCowswap } from "./helpers/lstrategy";
import { addSigner, withSigner } from "./helpers/sign";
import { mint, sleep, toObject } from "./helpers/utils";


task("lstrategy-backtest", "run backtest on univ3 vault")
    .addParam(
        "filename",
        "The name of the file with historical data",
        undefined,
        types.string,
    ).addParam(
        "width",
        "The width of the interval of positions",
        undefined,
        types.int,
    ).setAction(
        async ({ filename, width}, hre: HardhatRuntimeEnvironment) => {
            const context = await setup(hre);
            await process(filename, width, hre, context);
        }
    );


const setup = async (hre: HardhatRuntimeEnvironment) => {
    const uniV3PoolFee = 500;

    const { deployments, ethers, getNamedAccounts, network } = hre;
    const { deploy, read } = deployments;
    await deployments.fixture();

    const { admin, deployer, uniswapV3PositionManager, uniswapV3Router, weth, wsteth } =
        await getNamedAccounts();
    const swapRouter = await ethers.getContractAt(
        ISwapRouter,
        uniswapV3Router
    );
    const positionManager = await ethers.getContractAt(
        INonfungiblePositionManager,
        uniswapV3PositionManager
    );
    const adminSigned = await addSigner(hre, admin);
    const deployerSigned = await addSigner(hre, deployer);

    const protocolGovernance = await ethers.getContract("ProtocolGovernance");
    const wethContract = await ethers.getContractAt(IWETH, weth);
    const wstethContract = await ethers.getContractAt(IWSTETH, wsteth);

    await wethContract.approve(uniswapV3PositionManager, ethers.constants.MaxUint256);
    await wstethContract.approve(uniswapV3PositionManager, ethers.constants.MaxUint256);

    await protocolGovernance.connect(adminSigned).stagePermissionGrants(wsteth, [PermissionIdsLibrary.ERC20_VAULT_TOKEN]);
    await sleep(network, await protocolGovernance.governanceDelay());
    await protocolGovernance.connect(adminSigned).commitPermissionGrants(wsteth);

    const tokens = [weth, wsteth]
        .map((t) => t.toLowerCase())
        .sort();

    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
    let uniV3LowerVaultNft = startNft;
    let uniV3UpperVaultNft = startNft + 1;
    let erc20VaultNft = startNft + 2;
    let uniV3Helper = (await ethers.getContract("UniV3Helper"))
        .address;

    await setupVault(
        hre,
        uniV3LowerVaultNft,
        "UniV3VaultGovernance",
        {
            createVaultArgs: [
                tokens,
                deployerSigned.address,
                uniV3PoolFee,
                uniV3Helper,
            ],
        }
    );
    await setupVault(
        hre,
        uniV3UpperVaultNft,
        "UniV3VaultGovernance",
        {
            createVaultArgs: [
                tokens,
                deployerSigned.address,
                uniV3PoolFee,
                uniV3Helper,
            ],
        }
    );
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
        ],
        log: true,
        autoMine: true,
    });

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

    const erc20RootVaultContract = await ethers.getContractAt("ERC20RootVault", erc20RootVault);

    await
        protocolGovernance
            .connect(adminSigned)
            .stageValidator(
                wsteth,
                wstethValidator.address,
            );
    await sleep(network, await protocolGovernance.governanceDelay());
    await
        protocolGovernance
            .connect(adminSigned)
            .commitValidator(wsteth);
    
    let cowswapValidatorDeployParams = await deploy(
        "CowswapValidator",
        {
            from: deployerSigned.address,
            contract: "CowswapValidator",
            args: [protocolGovernance.address],
            log: true,
            autoMine: true,
        }
    );

    const cowswap = await ethers.getContractAt(
        "MockCowswap",
        cowswapDeployParams.address
    );

    await
        protocolGovernance
            .connect(adminSigned)
            .stageValidator(
                cowswap.address,
                cowswapValidatorDeployParams.address
            );
    
    await sleep(network, await protocolGovernance.governanceDelay());
    await
        protocolGovernance
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
        BigNumber.from(10).pow(18).mul(4000)
    );
    await mint(
        hre,
        "WETH",
        deployerSigned.address,
        BigNumber.from(10).pow(18).mul(4000)
    );
    await wethContract.approve(
        curvePool.address,
        ethers.constants.MaxUint256
    );
    await steth.approve(
        wstethContract.address,
        ethers.constants.MaxUint256
    );
    await wethContract.withdraw(BigNumber.from(10).pow(18).mul(2000));
    const options = { value: BigNumber.from(10).pow(18).mul(2000) };
    await curvePool.exchange(
        0,
        1,
        BigNumber.from(10).pow(18).mul(2000),
        ethers.constants.Zero,
        options
    );
    await wstethContract.wrap(BigNumber.from(10).pow(18).mul(1999));

    await wstethContract.transfer(
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

    await uniV3VaultGovernance
        .connect(adminSigned)
        .stageDelayedProtocolParams({
            positionManager: uniswapV3PositionManager,
            oracle: oracleDeployParams.address,
        });
    await sleep(network, 86400);
    await uniV3VaultGovernance
        .connect(adminSigned)
        .commitDelayedProtocolParams();

    await lstrategy
        .connect(adminSigned)
        .updateTradingParams({
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
        minErc20UniV3CapitalRatioDeviationD:
            BigNumber.from(10).pow(5),
        minErc20TokenRatioDeviationD: BigNumber.from(10)
            .pow(8)
            .div(2),
        minUniV3LiquidityRatioDeviationD: BigNumber.from(10)
            .pow(7)
            .div(5),
    });


    await lstrategy
        .connect(adminSigned)
        .updateOtherParams({
            intervalWidthInTicks: 100,
            minToken0ForOpening: BigNumber.from(10).pow(6),
            minToken1ForOpening: BigNumber.from(10).pow(6),
            rebalanceDeadline: BigNumber.from(10).pow(6),
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


const setupVault = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    contractName: string,
    {
        createVaultArgs,
        delayedStrategyParams,
        strategyParams,
        delayedProtocolPerVaultParams,
    }: {
        createVaultArgs: any[];
        delayedStrategyParams?: { [key: string]: any };
        strategyParams?: { [key: string]: any };
        delayedProtocolPerVaultParams?: { [key: string]: any };
    }
) => {
    delayedStrategyParams ||= {};
    const { deployments, ethers, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;
    const { deployer, admin } = await getNamedAccounts();
    const TRANSACTION_GAS_LIMITS = {
        maxFeePerGas: ethers.BigNumber.from(90000000000),
        maxPriorityFeePerGas: ethers.BigNumber.from(40000000000),
    }
    const currentNft = await read("VaultRegistry", "vaultsCount");
    if (currentNft <= expectedNft) {
        log(`Deploying ${contractName.replace("Governance", "")}...`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS
            },
            "createVault",
            ...createVaultArgs
        );
        log(`Done, nft = ${expectedNft}`);
    } else {
        log(
            `${contractName.replace(
                "Governance",
                ""
            )} with nft = ${expectedNft} already deployed`
        );
    }
    if (strategyParams) {
        const currentParams = await read(
            contractName,
            "strategyParams",
            expectedNft
        );

        if (!equals(strategyParams, toObject(currentParams))) {
            log(`Setting Strategy params for ${contractName}`);
            log(strategyParams);
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS
                },
                "setStrategyParams",
                expectedNft,
                strategyParams
            );
        }
    }
    let strategyTreasury;
    try {
        const data = await read(
            contractName,
            "delayedStrategyParams",
            expectedNft
        );
        strategyTreasury = data.strategyTreasury;
    } catch {
        return;
    }

    if (strategyTreasury !== delayedStrategyParams.strategyTreasury) {
        log(`Setting delayed strategy params for ${contractName}`);
        log(delayedStrategyParams);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS
            },
            "stageDelayedStrategyParams",
            expectedNft,
            delayedStrategyParams
        );
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
                ...TRANSACTION_GAS_LIMITS
            },
            "commitDelayedStrategyParams",
            expectedNft
        );
    }
    if (delayedProtocolPerVaultParams) {
        const params = await read(
            contractName,
            "delayedProtocolPerVaultParams",
            expectedNft
        );
        if (!equals(toObject(params), delayedProtocolPerVaultParams)) {
            log(
                `Setting delayed protocol per vault params for ${contractName}`
            );
            log(delayedProtocolPerVaultParams);

            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS
                },
                "stageDelayedProtocolPerVaultParams",
                expectedNft,
                delayedProtocolPerVaultParams
            );
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS
                },
                "commitDelayedProtocolPerVaultParams",
                expectedNft
            );
        }
    }
};

const combineVaults = async (
    hre: HardhatRuntimeEnvironment,
    expectedNft: number,
    nfts: number[],
    strategyAddress: string,
    strategyTreasuryAddress: string,
    options?: {
        limits?: BigNumberish[];
        strategyPerformanceTreasuryAddress?: string;
        tokenLimitPerAddress: BigNumberish;
        tokenLimit: BigNumberish;
        managementFee: BigNumberish;
        performanceFee: BigNumberish;
    }
): Promise<void> => {
    if (nfts.length === 0) {
        throw `Trying to combine 0 vaults`;
    }
    const { deployments, ethers } = hre;
    const { log } = deployments;
    const { deployer, admin } = await hre.getNamedAccounts();

    const TRANSACTION_GAS_LIMITS = {
        maxFeePerGas: ethers.BigNumber.from(90000000000),
        maxPriorityFeePerGas: ethers.BigNumber.from(40000000000),
    }
    const PRIVATE_VAULT = true;

    const firstNft = nfts[0];
    const firstAddress = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        firstNft
    );
    const vault = await hre.ethers.getContractAt("IVault", firstAddress);
    const tokens = await vault.vaultTokens();
    const coder = hre.ethers.utils.defaultAbiCoder;

    const {
        limits = tokens.map((_: any) => ethers.constants.MaxUint256),
        strategyPerformanceTreasuryAddress = strategyTreasuryAddress,
        tokenLimitPerAddress = ethers.constants.MaxUint256,
        tokenLimit = ethers.constants.MaxUint256,
        managementFee = 2 * 10 ** 7,
        performanceFee = 20 * 10 ** 7,
    } = options || {};

    await setupVault(hre, expectedNft, "ERC20RootVaultGovernance", {
        createVaultArgs: [tokens, strategyAddress, nfts, deployer],
        delayedStrategyParams: {
            strategyTreasury: strategyTreasuryAddress,
            strategyPerformanceTreasury: strategyPerformanceTreasuryAddress,
            managementFee: BigNumber.from(managementFee),
            performanceFee: BigNumber.from(performanceFee),
            privateVault: PRIVATE_VAULT,
            depositCallbackAddress: ethers.constants.AddressZero,
            withdrawCallbackAddress: ethers.constants.AddressZero,
        },
        strategyParams: {
            tokenLimitPerAddress: BigNumber.from(tokenLimitPerAddress),
            tokenLimit: BigNumber.from(tokenLimit),
        },
    });
    const rootVault = await deployments.read(
        "VaultRegistry",
        "vaultForNft",
        expectedNft
    );
    if (PRIVATE_VAULT) {
        const rootVaultContract = await hre.ethers.getContractAt(
            "ERC20RootVault",
            rootVault
        );
        const depositors = (await rootVaultContract.depositorsAllowlist()).map(
            (x: any) => x.toString()
        );
        if (!depositors.includes(admin)) {
            log("Adding admin to depositors");
            const tx =
                await rootVaultContract.populateTransaction.addDepositorsToAllowlist(
                    [admin]
                );
            const [operator] = await hre.ethers.getSigners();
            const txResp = await operator.sendTransaction(tx);
            log(
                `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
            );
            const receipt = await txResp.wait(1);
            log("Transaction confirmed");
        }
    }
    await deployments.execute(
        "VaultRegistry",
        { from: deployer, autoMine: true, ...TRANSACTION_GAS_LIMITS },
        "transferFrom(address,address,uint256)",
        deployer,
        rootVault,
        expectedNft
    );
};

const parseFile = (filename: string) : string[] =>  {
    const csvFilePath = path.resolve(__dirname, filename);
    const fileContent = fs.readFileSync(csvFilePath, { encoding: 'utf-8' });
    const fileLen = 26542;
    const blockNumberLen = 8;
    const pricePrecision = 29;
    let prices = new Array();

    let index = 0;
    for (let i = 0; i < fileLen; ++i) {
        //let blockNumber = fileContent.slice(index, index + blockNumberLen);
        let price = fileContent.slice(index + blockNumberLen + 1, index + blockNumberLen + pricePrecision + 1);
        prices.push(price);
        index += blockNumberLen + pricePrecision + 2;
    }

    return prices;

};

const changePrice = async (currentTick: BigNumber, context: Context) => {
    let sqrtPriceX96 = BigNumber.from(
        TickMath.getSqrtRatioAtTick(
            currentTick.toNumber()
        ).toString()
    );
    let priceX96 = sqrtPriceX96
        .mul(sqrtPriceX96)
        .div(BigNumber.from(2).pow(96));
    context.mockOracle.updatePrice(priceX96);
}

const mintMockPosition = async (hre : HardhatRuntimeEnvironment, context: Context) => {
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

const buildInitialPositions = async (hre: HardhatRuntimeEnvironment, context: Context, width: number) => {

    let tick = await getUniV3Tick(hre, context);
    await changePrice(tick, context);

    let semiPositionRange = width / 2;

    let tickLeftLower =
        tick
            .div(semiPositionRange)
            .mul(semiPositionRange).toNumber() - semiPositionRange;
    let tickLeftUpper = tickLeftLower + 2 * semiPositionRange;

    let tickRightLower = tickLeftLower + semiPositionRange;
    let tickRightUpper = tickLeftUpper + semiPositionRange;

    let lowerVault = await context.LStrategy.lowerVault();
    let upperVault = await context.LStrategy.upperVault();
    await preparePush({hre, context, vault: lowerVault, tickLower: tickLeftLower, tickUpper: tickLeftUpper});
    await preparePush({hre, context, vault: upperVault, tickLower: tickRightLower, tickUpper: tickRightUpper});

    let erc20 = await context.LStrategy.erc20Vault();
    for (let token of [context.weth, context.wsteth]) {
        await token.transfer(
        erc20,
        BigNumber.from(10).pow(18).mul(500)
        );
    }

};

const makeDesiredPoolPrice = async (hre: HardhatRuntimeEnvironment, context: Context, tick: BigNumber) => {

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
            
        }
        else {
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

const grantPermissions = async (hre: HardhatRuntimeEnvironment, context: Context, vault: string) => {
    const { ethers } = hre;
    const vaultRegistry = await ethers.getContract("VaultRegistry");
    let tokenId = await ethers.provider.send(
        "eth_getStorageAt",
        [
            vault,
            "0x4", // address of _nft
        ]
    );
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

const fullPriceUpdate = async (hre: HardhatRuntimeEnvironment, context: Context, tick: BigNumber) => {
    await makeDesiredPoolPrice(hre, context, tick);
    await changePrice(tick, context);
};

const assureEquality = (x: BigNumber, y: BigNumber) => {

    let delta = x.sub(y).abs();
    if (x.lt(y)) {
        x = y;
    }

    return (delta.mul(1000).lt(x));
};

const getCapital = async (hre: HardhatRuntimeEnvironment, context: Context, priceX96: BigNumber, address: string)  => {

    let tvls = await getTvl(hre, address);
    let minTvl = tvls[0];
    let maxTvl = tvls[1];

    return (minTvl[0].add(maxTvl[0])).div(2).mul(priceX96).div(BigNumber.from(2).pow(96)).add((minTvl[1].add(maxTvl[1])).div(2));
};

const ERC20UniRebalance = async(hre: HardhatRuntimeEnvironment, context: Context, priceX96: BigNumber) => {
    const { ethers } = hre;

    while (true) {

        let capitalErc20 = await getCapital(hre, context, priceX96, await context.LStrategy.erc20Vault());
        let capitalLower = await getCapital(hre, context, priceX96, await context.LStrategy.lowerVault());
        let capitalUpper = await getCapital(hre, context, priceX96, await context.LStrategy.upperVault());

        if (assureEquality(capitalErc20.mul(19), capitalLower.add(capitalUpper))) {
            break;
        }

        await context.LStrategy.connect(context.admin).rebalanceERC20UniV3Vaults(
            [
                ethers.constants.Zero,
                ethers.constants.Zero,
            ],
            [
                ethers.constants.Zero,
                ethers.constants.Zero,
            ],
            ethers.constants.MaxUint256
        );

        await makeSwap(hre, context);

    }
    
  //  expect(assureEquality(capitalErc20.mul(19), capitalLower.add(capitalUpper))).to.be.true;

};

const makeRebalances = async(hre: HardhatRuntimeEnvironment, context: Context, priceX96 : BigNumber) => {

    const { ethers } = hre;

    let wasRebalance = false;

    while (!(await checkUniV3Balance(hre, context))) {
        wasRebalance = true;
        await context.LStrategy.connect(context.admin).rebalanceUniV3Vaults([
            ethers.constants.Zero,
            ethers.constants.Zero,
        ],
        [
            ethers.constants.Zero,
            ethers.constants.Zero,
        ],
        ethers.constants.MaxUint256);
        await context.LStrategy.connect(context.admin).rebalanceERC20UniV3Vaults([
            ethers.constants.Zero,
            ethers.constants.Zero,
        ],
        [
            ethers.constants.Zero,
            ethers.constants.Zero,
        ],
        ethers.constants.MaxUint256);
        await makeSwap(hre, context);
    }

    if (wasRebalance) await ERC20UniRebalance(hre, context, priceX96);

};

const reportStats = async (hre: HardhatRuntimeEnvironment, context: Context, fname: string) => {
    const stats = await getStrategyStats(hre, context);
    const content = (
        stats.erc20token0.toString() + " " +
        stats.erc20token1.toString() + " " +
        stats.lowerVaultLiquidity.toString() + " " +
        stats.lowerVaultTokenOwed0.toString() + " " +
        stats.lowerVaultTokenOwed1.toString() + " " +
        stats.upperVaultLiquidity.toString() + " " +
        stats.upperVaultTokenOwed0.toString() + " " +
        stats.upperVaultTokenOwed1.toString() + "\n"
    );
    fs.writeFile(fname, content, { flag: "a+"}, err => {});
};

const process = async (filename: string, width: number, hre: HardhatRuntimeEnvironment, context: Context) => {

    await mintMockPosition(hre, context);
    
    let prices = parseFile(filename);

    await fullPriceUpdate(hre, context, getTick(stringToSqrtPriceX96(prices[0])));
    await buildInitialPositions(hre, context, width);
    const lowerVault = await context.LStrategy.lowerVault();
    const upperVault = await context.LStrategy.upperVault();
    const erc20vault = await context.LStrategy.erc20Vault();
    await grantPermissions(hre, context, lowerVault);
    await grantPermissions(hre, context, upperVault);
    await grantPermissions(hre, context, erc20vault);

    console.log("erc20Vault: ", erc20vault);

    await ERC20UniRebalance(hre, context, stringToPriceX96(prices[0]));

    const tmp = await context.LStrategy.erc20Vault();

    let prev = Date.now();
    for (let i = 1; i < 100; ++i) {
        console.log(i);
        reportStats(hre, context, "output.csv");
        await fullPriceUpdate(hre, context, getTick(stringToSqrtPriceX96(prices[i])));
        await makeRebalances(hre, context, stringToPriceX96(prices[i]));
        let current = Date.now();
    }
    console.log("Duration: ", Date.now() - prev);
};
