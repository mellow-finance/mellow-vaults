import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "../test/helpers/curvePoolABI.json";
import { abi as IWETH } from "../test/helpers/wethABI.json";
import { abi as IWSTETH } from "../test/helpers/wstethABI.json";
import { BigNumber } from "@ethersproject/bignumber";
import { task, types } from "hardhat/config";
import { BigNumberish, Contract, PopulatedTransaction } from "ethers";
import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import { FullMath, TickMath } from "@uniswap/v3-sdk";
import {
    any,
    equals,
    filter,
    fromPairs,
    keys,
    KeyValuePair,
    map,
    pipe,
} from "ramda";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { randomBytes } from "crypto";
import * as fs from "fs";
import * as path from "path";
import { float } from "fast-check";
import JSBI from "jsbi";
import { start } from "repl";
import { expect } from "chai";
import { sqrt } from "@uniswap/sdk-core";


type Context = {
    protocolGovernance: Contract;
    swapRouter: Contract;
    positionManager: Contract;
    LStrategy: Contract;
    weth: Contract;
    wsteth: Contract;
    admin: SignerWithAddress;
    deployer: SignerWithAddress;
    mockOracle: Contract;
    erc20RootVault: Contract;
};

task("lstrategy-slippage", "test slippages losses of LStrategy")
    .addParam(
        "tickchange",
        "Tick change done by the sandwicher",
        undefined,
        types.int,
    )
    .addParam(
        "erc20ratio",
        "Desired erc20ratio (5% if you want smth default)",
        undefined,
        types.int,
    )
    .addParam(
        "percentagechange",
        "Percentage flocking of capital during a rebalance",
        undefined,
        types.int,
    ).setAction(
        async ({tickchange, erc20ratio, percentagechange}, hre: HardhatRuntimeEnvironment) => {
            const context = await setup(hre, tickchange * 2);
            await process(tickchange, erc20ratio, percentagechange, hre, context);
        }
    );

const initialMint = async (hre : HardhatRuntimeEnvironment) => {

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
}


const setup = async (hre: HardhatRuntimeEnvironment, width : number) => {

    await initialMint(hre);

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
            width
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

    for (let i = 0; i < 30; ++i) {

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

    }

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

const preparePush = async ({
    hre,
    context,
    vault,
    tickLower = -887220,
    tickUpper = 887220,
    wethAmount = BigNumber.from(10).pow(9),
    wstethAmount = BigNumber.from(10).pow(9),
}: {
    hre: HardhatRuntimeEnvironment;
    context: Context
    vault: any;
    tickLower?: number;
    tickUpper?: number;
    wethAmount?: BigNumber;
    wstethAmount?: BigNumber;
}) => {
    const { ethers} = hre;
    const mintParams = {
        token0: context.wsteth.address,
        token1: context.weth.address,
        fee: 500,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: wstethAmount,
        amount1Desired: wethAmount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: context.deployer.address,
        deadline: ethers.constants.MaxUint256,
    };
    const result = await context.positionManager.callStatic.mint(
        mintParams
    );
    await context.positionManager.mint(mintParams);
    await context.positionManager.functions[
        "safeTransferFrom(address,address,uint256)"
    ](context.deployer.address, vault, result.tokenId);
};

const getTvl = async (
        hre: HardhatRuntimeEnvironment,
        address: string
) => {
    const { ethers } = hre;
    let vault = await ethers.getContractAt("IVault", address);
    let tvls = await vault.tvl();
    return tvls;
}

const getUniV3Tick = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const { ethers } = hre;
    let lowerVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.lowerVault()
    );
    let pool = await ethers.getContractAt(
        "IUniswapV3Pool",
        await lowerVault.pool()
    );

    const currentState = await pool.slot0();
    return BigNumber.from(currentState.tick);
};

const getPriceX96 = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const { ethers } = hre;
    let lowerVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.lowerVault()
    );
    let pool = await ethers.getContractAt(
        "IUniswapV3Pool",
        await lowerVault.pool()
    );

    const currentState = await pool.slot0();
    const sqrtPriceX96 = currentState.sqrtPriceX96

    return sqrtPriceX96.mul(sqrtPriceX96).div(BigNumber.from(2).pow(96));
};

const addSigner = async (
    hre: HardhatRuntimeEnvironment,
    address: string
): Promise<SignerWithAddress> => {
    const { ethers, network } = hre;
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
    });
    await network.provider.send("hardhat_setBalance", [
        address,
        "0x1000000000000000000",
    ]);
    return await ethers.getSigner(address);
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


const sleep = async (network: Network, seconds: BigNumberish) => {
    await network.provider.send("evm_increaseTime", [
        BigNumber.from(seconds).toNumber(),
    ]);
    await network.provider.send("evm_mine");
};

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

const toObject = (obj: any) =>
    pipe(
        keys,
        filter((x: string) => isNaN(parseInt(x))),
        map((x) => [x, obj[x]] as KeyValuePair<string, any>),
        fromPairs
    )(obj);

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

type MintableToken = "USDC" | "WETH" | "WBTC";

const mint = async (
    hre: HardhatRuntimeEnvironment,
    token: MintableToken | string,
    to: string,
    amount: BigNumberish
) => {
    const { ethers, getNamedAccounts } = hre;
    const { wbtc, weth, usdc } = await getNamedAccounts();
    switch (token.toLowerCase()) {
        case wbtc.toLowerCase():
            token = "WBTC";
            break;
        case weth.toLowerCase():
            token = "WETH";
            break;
        case usdc.toLowerCase():
            token = "USDC";
            break;

        default:
            break;
    }
    switch (token) {
        case "USDC":
            // masterMinter()
            let minter = await ethers.provider.call({
                to: usdc,
                data: `0x35d99f35`,
            });
            minter = `0x${minter.substring(2 + 12 * 2)}`;
            await withSigner(hre, minter, async (s) => {
                // function configureMinter(address minter, uint256 minterAllowedAmount)
                let tx: PopulatedTransaction = {
                    to: usdc,
                    from: minter,
                    data: `0x4e44d956${ethers.utils
                        .hexZeroPad(s.address, 32)
                        .substring(2)}${ethers.utils
                        .hexZeroPad(BigNumber.from(amount).toHexString(), 32)
                        .substring(2)}`,
                    gasLimit: BigNumber.from(10 ** 6),
                };

                let resp = await s.sendTransaction(tx);
                await resp.wait();

                // function mint(address,uint256)
                tx = {
                    to: usdc,
                    from: minter,
                    data: `0x40c10f19${ethers.utils
                        .hexZeroPad(to, 32)
                        .substring(2)}${ethers.utils
                        .hexZeroPad(BigNumber.from(amount).toHexString(), 32)
                        .substring(2)}`,
                    gasLimit: BigNumber.from(10 ** 6),
                };

                resp = await s.sendTransaction(tx);
                await resp.wait();
            });
            break;

        case "WETH":
            const addr = randomAddress(hre);
            await withSigner(hre, addr, async (s) => {
                // deposit()
                const tx: PopulatedTransaction = {
                    to: weth,
                    from: addr,
                    data: `0xd0e30db0`,
                    gasLimit: BigNumber.from(10 ** 6),
                    value: BigNumber.from(amount),
                };
                const resp = await s.sendTransaction(tx);
                await resp.wait();
                const c = await ethers.getContractAt("ERC20Token", weth);
                await c.connect(s).transfer(to, amount);
            });
            break;
        case "WBTC":
            // owner()
            let owner = await ethers.provider.call({
                to: wbtc,
                data: `0x8da5cb5b`,
            });
            owner = `0x${owner.substring(2 + 12 * 2)}`;
            await withSigner(hre, owner, async (s) => {
                // function mint(address,uint256)
                const tx = {
                    to: wbtc,
                    from: owner,
                    data: `0x40c10f19${ethers.utils
                        .hexZeroPad(to, 32)
                        .substring(2)}${ethers.utils
                        .hexZeroPad(BigNumber.from(amount).toHexString(), 32)
                        .substring(2)}`,
                    gasLimit: BigNumber.from(10 ** 6),
                };

                const resp = await s.sendTransaction(tx);
                await resp.wait();
            });
            break;

        default:
            throw `Unknown token: ${token}`;
    }
};

const randomAddress = (hre: HardhatRuntimeEnvironment) => {
    const { ethers } = hre;
    const id = randomBytes(32).toString("hex");
    const privateKey = "0x" + id;
    const wallet = new ethers.Wallet(privateKey);
    return wallet.address;
};

export const withSigner = async (
    hre: HardhatRuntimeEnvironment,
    address: string,
    f: (signer: SignerWithAddress) => Promise<void>
) => {
    const signer = await addSigner(hre, address);
    await f(signer);
    await removeSigner(hre.network, address);
};

const removeSigner = async (network: Network, address: string) => {
    await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [address],
    });
};

const changePrice = async (currentTick: BigNumber, hre: HardhatRuntimeEnvironment, context: Context) => {
    let priceX96 = await getPriceX96(hre, context);
    await context.mockOracle.updatePrice(priceX96);
}

const swapTokens = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    senderAddress: string,
    recipientAddress: string,
    tokenIn: Contract,
    tokenOut: Contract,
    amountIn: BigNumber
) => {
    const { ethers } = hre;
    await withSigner(hre, senderAddress, async (senderSigner) => {
        await tokenIn
            .connect(senderSigner)
            .approve(
                context.swapRouter.address,
                ethers.constants.MaxUint256
            );
        let params = {
            tokenIn: tokenIn.address,
            tokenOut: tokenOut.address,
            fee: 500,
            recipient: recipientAddress,
            deadline: ethers.constants.MaxUint256,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0,
        };
        await context.swapRouter
            .connect(senderSigner)
            .exactInputSingle(params);
    });
};

const buildInitialPositions = async (hre: HardhatRuntimeEnvironment, context: Context, width: number) => {

    const { ethers } = hre;
    let tick = await getUniV3Tick(hre, context);
    await changePrice(tick, hre, context);

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
        BigNumber.from(10).pow(18).mul(30000)
        );
    }
};


const getPool = async (hre: HardhatRuntimeEnvironment, context: Context) => {
    const { ethers } = hre;
    let lowerVault = await ethers.getContractAt(
        "IUniV3Vault",
        await context.LStrategy.lowerVault()
    );
    let pool = await ethers.getContractAt(
        "IUniswapV3Pool",
        await lowerVault.pool()
    );
    return pool;
};

let wethProfit = BigNumber.from(0);
let wstethProfit = BigNumber.from(0);

let wethUsed = BigNumber.from(0);
let wstethUsed = BigNumber.from(0);

const makeDesiredPoolPrice = async (hre: HardhatRuntimeEnvironment, context: Context, tick: BigNumber, isMock: boolean) => {

    let pool = await getPool(hre, context);

    let startTry = BigNumber.from(10).pow(19).mul(3);

    let needIncrease = 0; //mock initialization

    let wethStart = await context.weth.balanceOf(context.deployer.address);
    let wstethStart = await context.wsteth.balanceOf(context.deployer.address);
    
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
            if (!isMock) {
                wethUsed = wethUsed.add(startTry);
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
            if (!isMock) {
                wstethUsed = wstethUsed.add(startTry);
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

    let wethEnd = await context.weth.balanceOf(context.deployer.address);
    let wstethEnd = await context.wsteth.balanceOf(context.deployer.address);

    if (!isMock) {
        wethProfit = wethProfit.add(wethEnd.sub(wethStart));
        wstethProfit = wstethProfit.add(wstethEnd.sub(wstethStart));
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

const getCapital = async (hre: HardhatRuntimeEnvironment, context: Context, priceX96: BigNumber, address: string)  => {

    let tvls = await getTvl(hre, address);
    let minTvl = tvls[0];
    let maxTvl = tvls[1];

    return (minTvl[0].add(maxTvl[0])).div(2).mul(priceX96).div(BigNumber.from(2).pow(96)).add((minTvl[1].add(maxTvl[1])).div(2));
};

const getCapitalbyTokens = async (hre: HardhatRuntimeEnvironment, context: Context, priceX96: BigNumber, token0: BigNumber, token1: BigNumber)  => {

    return token0.mul(priceX96).div(BigNumber.from(2).pow(96)).add(token1);
};

const assureEquality = async (hre: HardhatRuntimeEnvironment, context: Context, ratio: number) => {

    let priceX96 = await getPriceX96(hre, context);
                        
    let capitalErc20 = await getCapital(hre, context, priceX96, await context.LStrategy.erc20Vault());
    let capitalLower = await getCapital(hre, context, priceX96, await context.LStrategy.lowerVault());
    let capitalUpper = await getCapital(hre, context, priceX96, await context.LStrategy.upperVault());

    let capitalFirst = capitalErc20.mul(100 - ratio);   
    let capitalSecond = (capitalLower.add(capitalUpper)).mul(ratio);

    let delta = capitalFirst.sub(capitalSecond).abs();
    let maxBetweenCapitals = capitalFirst;

    if (capitalFirst.lt(capitalSecond)) {
        maxBetweenCapitals = capitalSecond;
    }

    return (delta.mul(100).lt(maxBetweenCapitals));
};

const setInitialPrice = async (hre: HardhatRuntimeEnvironment, context: Context, tick: number, isMock: boolean) => {
    await makeDesiredPoolPrice(hre, context, BigNumber.from(tick), isMock);
    await changePrice(BigNumber.from(tick), hre, context);
}

const swapWethToWsteth = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    amountIn: BigNumber,
    minAmountOut: BigNumber,
    tickPrice: number
) => {
    const erc20 = await context.LStrategy.erc20Vault();
    const { deployer, wsteth, weth } = context;
    const { ethers } = hre;
    let erc20address = await context.LStrategy.erc20Vault();
    const erc20Vault = await ethers.getContractAt(
        "ERC20Vault",
        erc20address,
    );
    const sqrtPricex96 = BigNumber.from(TickMath.getSqrtRatioAtTick(tickPrice).toString());
    const priceX96 = sqrtPricex96.mul(sqrtPricex96).div(BigNumber.from(2).pow(96));

    const denominator = BigNumber.from(2).pow(96);
    const balance = await wsteth.balanceOf(deployer.address);
    let expectedOut = amountIn.mul(denominator).div(priceX96);

    if (expectedOut.gt(balance)) {
        expectedOut = balance;
    }
    if (expectedOut.lt(minAmountOut)) {
        return;
    }
    await withSigner(hre, erc20, async (signer) => {
        await weth.connect(signer).transfer(deployer.address, amountIn);
    });
    await wsteth.connect(deployer).transfer(erc20, expectedOut);
};

const swapWstethToWeth = async (
    hre: HardhatRuntimeEnvironment,
    context: Context,
    amountIn: BigNumber,
    minAmountOut: BigNumber,
    tickPrice: number
) => {
    const erc20 = await context.LStrategy.erc20Vault();
    const { deployer, wsteth, weth } = context;
    const { ethers } = hre;
    let erc20address = await context.LStrategy.erc20Vault();
    const erc20Vault = await ethers.getContractAt(
        "ERC20Vault",
        erc20address,
    );

    const sqrtPricex96 = BigNumber.from(TickMath.getSqrtRatioAtTick(tickPrice).toString());
    const priceX96 = sqrtPricex96.mul(sqrtPricex96).div(BigNumber.from(2).pow(96));

    const balance = await weth.balanceOf(deployer.address);
    let expectedOut = amountIn.mul(priceX96).div(BigNumber.from(2).pow(96));

    if (expectedOut.gt(balance)) {
        expectedOut = balance;
    }
    if (expectedOut.lt(minAmountOut)) {
        return;
    }
    await withSigner(hre, erc20, async (signer) => {
        await wsteth.connect(signer).transfer(deployer.address, amountIn);
    });
    await weth.connect(deployer).transfer(erc20, expectedOut);
};

const makeSwap = async (hre: HardhatRuntimeEnvironment, context: Context, honestTick: number) => {

    const { ethers } = hre;

    let erc20Vault = await context.LStrategy.erc20Vault();
    let vault = await ethers.getContractAt(
        "IVault",
        erc20Vault
    );

    let erc20Tvl = await vault.tvl();
    let delta = erc20Tvl[0][0].sub(erc20Tvl[0][1]);

    if (delta.lt(BigNumber.from(-1))) {
        await swapWethToWsteth(
            hre, context, delta.div(2).mul(-1), BigNumber.from(0), honestTick
        );
    }

    if (delta.gt(BigNumber.from(1))) {
        await swapWstethToWeth(
            hre, context, delta.div(2), BigNumber.from(0), honestTick
        );
    }
};

const erc20Rebalance = async(hre: HardhatRuntimeEnvironment, context: Context, ratio: number, honestTick: number) => {

    const { ethers } = hre;

    while (true) {
        if (await assureEquality(hre, context, ratio)) {
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
        await makeSwap(hre, context, honestTick);
    }

};

const changeParams = async(hre: HardhatRuntimeEnvironment, context: Context, newRatio : BigNumber) => {
    const baseParams = {
        erc20UniV3CapitalRatioD: newRatio,
        erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5),
        minErc20UniV3CapitalRatioDeviationD:
            BigNumber.from(10).pow(5),
        minErc20TokenRatioDeviationD: BigNumber.from(10).pow(7),
        minUniV3LiquidityRatioDeviationD:
            BigNumber.from(10).pow(7),
    };
    await context.LStrategy
        .connect(context.admin)
        .updateRatioParams(baseParams);
}

const allCapital = async(hre: HardhatRuntimeEnvironment, context: Context, priceX96: BigNumber) => {

    let capitalErc20 = await getCapital(hre, context, priceX96, await context.LStrategy.erc20Vault());
    let capitalLower = await getCapital(hre, context, priceX96, await context.LStrategy.lowerVault());
    let capitalUpper = await getCapital(hre, context, priceX96, await context.LStrategy.upperVault());
    return (capitalErc20).add(capitalLower).add(capitalUpper);
}

const process = async (tickChange: number, erc20ratio: number, percentagechange: number, hre: HardhatRuntimeEnvironment, context: Context) => {

    let tick = await getUniV3Tick(hre, context);

    let percentageChange = percentagechange;

    const width = 200;
    const startPrice = tick.toNumber();
    const finishPrice = tick.toNumber() + tickChange;

    await changeParams(hre, context, BigNumber.from(10).pow(7).mul(erc20ratio));

    await setInitialPrice(hre, context, startPrice, true);

    await buildInitialPositions(hre, context, width);

    const lowerVault = await context.LStrategy.lowerVault();
    const upperVault = await context.LStrategy.upperVault();
    const erc20vault = await context.LStrategy.erc20Vault();
    await grantPermissions(hre, context, lowerVault);
    await grantPermissions(hre, context, upperVault);
    await grantPermissions(hre, context, erc20vault);
    
    await erc20Rebalance(hre, context, erc20ratio, startPrice);

    expect(await assureEquality(hre, context, erc20ratio)).to.be.true;

    await changeParams(hre, context, BigNumber.from(10).pow(7).mul(erc20ratio + percentageChange));
    await erc20Rebalance(hre, context, erc20ratio + percentageChange, startPrice);
    expect(await assureEquality(hre, context, erc20ratio + percentageChange)).to.be.true;

    await changeParams(hre, context, BigNumber.from(10).pow(7).mul(erc20ratio));
    await erc20Rebalance(hre, context, erc20ratio, startPrice);
    expect(await assureEquality(hre, context, erc20ratio)).to.be.true;
    let globalPriceX96 = await getPriceX96(hre, context);
    let totalNormalCapital = await allCapital(hre, context, globalPriceX96);

    await changeParams(hre, context, BigNumber.from(10).pow(7).mul(erc20ratio + percentageChange));
    await erc20Rebalance(hre, context, erc20ratio + percentageChange, startPrice);
    expect(await assureEquality(hre, context, erc20ratio + percentageChange)).to.be.true;

    await setInitialPrice(hre, context, finishPrice, false);
    expect(finishPrice).to.be.eq(await getUniV3Tick(hre, context));

    await changeParams(hre, context, BigNumber.from(10).pow(7).mul(erc20ratio));
    await erc20Rebalance(hre, context, erc20ratio, startPrice);
    expect(await assureEquality(hre, context, erc20ratio)).to.be.true;

    await setInitialPrice(hre, context, startPrice, false);
    expect(startPrice).to.be.eq(await getUniV3Tick(hre, context))
    let totalBadCapital = await allCapital(hre, context, globalPriceX96);

    let loss = totalNormalCapital.sub(totalBadCapital);

    console.log("10^-6 LOSS", (loss.mul(1000000).div(totalNormalCapital)).toNumber());

    let sandwicherProfit = await getCapitalbyTokens(hre, context, globalPriceX96, wstethProfit, wethProfit);
    let sandwicherDeals = await getCapitalbyTokens(hre, context, globalPriceX96, wstethUsed, wethUsed);

    console.log("10^-6 SANDWICHER PROFIT", (sandwicherProfit.mul(1000000).div(sandwicherDeals)).toNumber());
    console.log("ETH USED", sandwicherDeals.div(BigNumber.from(10).pow(18).mul(2)));
    expect(sandwicherProfit).to.be.lt(loss);

   // expect(totalNormalCapital.mul(997)).to.be.lt(totalBadCapital.mul(1000));
};