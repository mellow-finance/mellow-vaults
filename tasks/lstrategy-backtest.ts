import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "../test/helpers/curvePoolABI.json";
import { abi as IWETH } from "../test/helpers/wethABI.json";
import { abi as IWSTETH } from "../test/helpers/wstethABI.json";
import { BigNumber } from "@ethersproject/bignumber";
import { task, types } from "hardhat/config";
import { BigNumberish, Contract, PopulatedTransaction } from "ethers";
import { HardhatRuntimeEnvironment, Network } from "hardhat/types";
import {
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
};

task("lstrategy-backtest", "run backtest on univ3 vault")
    .addParam(
        "filename",
        "The name of the file with historical data",
        undefined,
        types.string,
    ).setAction(
        async ({ filename }, hre: HardhatRuntimeEnvironment) => {
            const context = await setup(hre);
            await process(filename, hre, context);
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
    } as Context;
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

const process = async (filename: string, hre: HardhatRuntimeEnvironment, context: Context) => {
    const { ethers, network } = hre;
    const result = await context.LStrategy.connect(context.admin).rebalanceERC20UniV3Vaults(
        [ethers.constants.Zero, ethers.constants.Zero],
        [ethers.constants.Zero, ethers.constants.Zero],
        ethers.constants.MaxUint256,
    );
    const lowerVault = await context.LStrategy.lowerVault();
    console.log(lowerVault);
};
