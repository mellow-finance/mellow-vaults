import hre, { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {
    ALL_NETWORKS,
    combineVaults,
    MAIN_NETWORKS,
    setupVault, TRANSACTION_GAS_LIMITS,
} from "./0000_utils";
import { BigNumber } from "ethers";
import { map } from "ramda";
import { TickMath } from "@uniswap/v3-sdk";
import { sqrt } from "@uniswap/sdk-core";
import JSBI from "jsbi";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, log, execute } = deployments;
    const {
        approver,
        deployer,
        uniswapV3PositionManager,
        cowswap,
        cowswapRelayer,
        weth,
        wsteth,
        mStrategyTreasury,
        mStrategyAdmin,
    } = await getNamedAccounts();
    const tokens = [weth, wsteth].map((t) => t.toLowerCase()).sort();
    // const startNft =
    //     (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let uniV3LowerVaultNft = 37;
    let uniV3UpperVaultNft = 38;
    let erc20VaultNft = 39;
    const intervalWidthInTicks = 100;

    const positionManager = await ethers.getContractAt(
        "INonfungiblePositionManager",
        uniswapV3PositionManager
    );

    const preparePush = async (
        vault: string,
        tickLower: number,
        tickUpper: number,
        nft: number) => {

        const lStrategy = await ethers.getContract("LStrategy");
        const vaultRegistry = await ethers.getContract("VaultRegistry");

        log("approving", approver, nft);
        await vaultRegistry.approve(approver, nft, {...TRANSACTION_GAS_LIMITS});
        log("approved!");

        let signer = await ethers.getSigner(approver);

        const wethContract = await ethers.getContractAt("ERC20Token", weth);
        const wstethContract = await ethers.getContractAt("ERC20Token", wsteth);
        const amount = BigNumber.from(10).pow(12);

        log("approve tokens");
        await wethContract.approve(
            uniswapV3PositionManager,
            amount, {...TRANSACTION_GAS_LIMITS}
        );
        await wstethContract.approve(
            uniswapV3PositionManager,
            amount, {...TRANSACTION_GAS_LIMITS}
        );

        const mintParams = {
            token0: wsteth,
            token1: weth,
            fee: 500,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount,
            amount1Desired: amount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: approver,
            deadline: ethers.constants.MaxUint256,
        };
        log("Minting...");
        const result = await positionManager.callStatic.mint(
            mintParams
        );

        await positionManager.mint(mintParams, {...TRANSACTION_GAS_LIMITS});

        log("Transferring...");
        await positionManager.connect(signer).functions[
            "safeTransferFrom(address,address,uint256)"
        ](approver, vault, result.tokenId);
        log("Transferred!");

        vaultRegistry.approve(lStrategy.address, nft, {...TRANSACTION_GAS_LIMITS});

    };

    const uniV3Helper = (await ethers.getContract("UniV3Helper")).address;

    log("Setting up vaults");

    await setupVault(hre, uniV3LowerVaultNft, "UniV3VaultGovernance", {
        createVaultArgs: [tokens, deployer, 500, uniV3Helper],
    });
    await setupVault(hre, uniV3UpperVaultNft, "UniV3VaultGovernance", {
        createVaultArgs: [tokens, deployer, 500, uniV3Helper],
    });
    await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
        createVaultArgs: [tokens, deployer],
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

    const getUniV3Tick = async () => {

        const lStrategy = await ethers.getContract("LStrategy");
        const mellowOracle = await ethers.getContract("MellowOracle");

        const tradingParams = {
            oracle: mellowOracle.address,
            maxSlippageD: BigNumber.from(10).pow(7),
            oracleSafetyMask: 0x2A,
            orderDeadline: 86400 * 30,
            maxFee0: BigNumber.from(10).pow(15),
            maxFee1: BigNumber.from(10).pow(15)
        };

        const priceX96 = await lStrategy.getTargetPriceX96(
            tokens[0],
            tokens[1],
            tradingParams
        );

        const sqrtPriceX48 = BigNumber.from(sqrt(JSBI.BigInt(priceX96)).toString());
        const denominator = BigNumber.from(2).pow(48);
        const tick = TickMath.getTickAtSqrtRatio(JSBI.BigInt(sqrtPriceX48.mul(denominator)));

        return BigNumber.from(tick);
    };

    let strategyOrderHelper = await deploy("LStrategyHelper", {
        from: deployer,
        contract: "LStrategyHelper",
        args: [cowswap],
        log: true,
        autoMine: true,
    });

    let strategyDeployParams = await deploy("LStrategy", {
        from: deployer,
        contract: "LStrategy",
        args: [
            uniswapV3PositionManager,
            cowswap,
            cowswapRelayer,
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            strategyOrderHelper.address,
            deployer,
            120,
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });

    const lStrategy = await ethers.getContract("LStrategy");

    const semiPositionRange = Math.floor(intervalWidthInTicks / 2);

    const currentTick = await getUniV3Tick();
    let tickLeftLower =
        currentTick.div(semiPositionRange).mul(semiPositionRange)
            .toNumber() - semiPositionRange;
    let tickLeftUpper = tickLeftLower + intervalWidthInTicks;

    let tickRightLower = tickLeftLower + semiPositionRange;
    let tickRightUpper = tickLeftUpper + semiPositionRange;

    log("Make UniV3Positions");

    await preparePush(uniV3LowerVault, tickLeftLower, tickLeftUpper, uniV3LowerVaultNft);
    await preparePush(uniV3UpperVault, tickRightLower, tickRightUpper, uniV3UpperVaultNft);

    log("Combining vaults");

    await combineVaults(
        hre,
        erc20VaultNft + 1,
        [erc20VaultNft, uniV3LowerVaultNft, uniV3UpperVaultNft],
        strategyDeployParams.address,
        mStrategyTreasury
    );

    log("Combined!");

    const rootVaultAddress = await read(
        "VaultRegistry",
        "vaultForNft",
        uniV3UpperVaultNft
    );

    await deployments.save(`LStrategy_RootVault`, {
        abi: (await deployments.get("ERC20RootVault")).abi,
        address: rootVaultAddress,
    });

    const mellowOracle = await get("MellowOracle");

    log("Setting Params");

    await lStrategy.updateTradingParams({
        oracle: mellowOracle.address,
        maxSlippageD: BigNumber.from(10).pow(7),
        orderDeadline: 86400 * 30,
        oracleSafetyMask: 0x20,
        maxFee0: BigNumber.from(10).pow(15),
        maxFee1: BigNumber.from(10).pow(15)
    }, {...TRANSACTION_GAS_LIMITS});

    await lStrategy.updateRatioParams({
        erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR
        erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
        minErc20UniV3CapitalRatioDeviationD: BigNumber.from(10).pow(8),
        minErc20TokenRatioDeviationD: BigNumber.from(10).pow(8).div(2),
        minUniV3LiquidityRatioDeviationD: BigNumber.from(10).pow(8).div(2),
    }, {...TRANSACTION_GAS_LIMITS});
    await lStrategy.updateOtherParams({
        minToken0ForOpening: BigNumber.from(10).pow(6),
        minToken1ForOpening: BigNumber.from(10).pow(6),
        secondsBetweenRebalances: 600,
    }, {...TRANSACTION_GAS_LIMITS});

    log("Set Params");
    const ADMIN_ROLE =
    "0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8"; // keccak256("admin)
    const ADMIN_DELEGATE_ROLE =
        "0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7"; // keccak256("admin_delegate")
    const OPERATOR_ROLE =
        "0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622"; // keccak256("operator")

    await lStrategy.grantRole(ADMIN_ROLE, mStrategyAdmin, {...TRANSACTION_GAS_LIMITS});
    await lStrategy.grantRole(ADMIN_DELEGATE_ROLE, mStrategyAdmin, {...TRANSACTION_GAS_LIMITS});
    await lStrategy.renounceRole(ADMIN_ROLE, deployer, {...TRANSACTION_GAS_LIMITS});
};

export default func;
func.tags = ["LStrategy", ...MAIN_NETWORKS];
func.dependencies = [
    "ProtocolGovernance",
    "VaultRegistry",
    "MellowOracle",
    "UniV3VaultGovernance",
    "ERC20VaultGovernance",
];
