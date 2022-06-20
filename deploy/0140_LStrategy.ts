import hre, { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {
    ALL_NETWORKS,
    combineVaults,
    MAIN_NETWORKS,
    setupVault,
} from "./0000_utils";
import { BigNumber } from "ethers";
import { map } from "ramda";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, log, execute } = deployments;
    const {
        deployer,
        uniswapV3PositionManager,
        cowswap,
        weth,
        wsteth,
        mStrategyTreasury,
        mStrategyAdmin,
    } = await getNamedAccounts();
    const tokens = [weth, wsteth].map((t) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

    let uniV3LowerVaultNft = startNft;
    let uniV3UpperVaultNft = startNft + 1;
    let erc20VaultNft = startNft + 2;
    const intervalWidthInTicks = 120;

    const positionManager = await ethers.getContractAt(
        "INonfungiblePositionManager",
        uniswapV3PositionManager
    );

    const preparePush = async (
        vault: string,
        tickLower: number,
        tickUpper: number) => {
/*
        await weth.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
        await this.wsteth.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
*/
        const amount = BigNumber.from(10).pow(12);
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
            recipient: deployer,
            deadline: ethers.constants.MaxUint256,
        };
        const result = await positionManager.mint(mintParams);
        await positionManager.functions[
            "safeTransferFrom(address,address,uint256)"
        ](deployer, vault, result.tokenId);
    };

    const uniV3Helper = (await ethers.getContract("UniV3Helper")).address;

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

        console.log(uniV3LowerVault);

        let vault = await ethers.getContractAt(
            "IVault",
            uniV3LowerVault
        );

        console.log(vault);

        let pool = await ethers.getContractAt(
            "IUniswapV3Pool",
            await vault.pool()
        );
        console.log(pool);
        
        const currentState = await pool.slot0();
        console.log(currentState);
        return BigNumber.from(currentState.tick);
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
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            strategyOrderHelper.address,
            deployer,
            intervalWidthInTicks,
        ],
        log: true,
        autoMine: true,
    });

    await combineVaults(
        hre,
        erc20VaultNft + 1,
        [erc20VaultNft, uniV3LowerVaultNft, uniV3UpperVaultNft],
        strategyDeployParams.address,
        mStrategyTreasury
    );

    const semiPositionRange = 60;

    const currentTick = await getUniV3Tick();
    let tickLeftLower =
        currentTick
            .div(semiPositionRange)
            .mul(semiPositionRange)
            .toNumber() - semiPositionRange;
    let tickLeftUpper = tickLeftLower + 2 * semiPositionRange;

    let tickRightLower = tickLeftLower + semiPositionRange;
    let tickRightUpper = tickLeftUpper + semiPositionRange;

    preparePush(uniV3LowerVault.address, tickLeftLower, tickLeftUpper);
    preparePush(uniV3UpperVault.address, tickRightLower, tickRightUpper);

    const lStrategy = await ethers.getContract("LStrategy");
    const mellowOracle = await get("MellowOracle");

    await lStrategy.updateTradingParams({
        oracle: mellowOracle.address,
        maxSlippageD: BigNumber.from(10).pow(7),
        oracleSafetyMask: 0x20,
        orderDeadline: 86400 * 30,
        maxFee0: BigNumber.from(10).pow(15),
        maxFee1: BigNumber.from(10).pow(15)
    });

    await lStrategy.updateRatioParams({
        erc20UniV3CapitalRatioD: BigNumber.from(10).pow(7).mul(5), // 0.05 * DENOMINATOR
        erc20TokenRatioD: BigNumber.from(10).pow(8).mul(5), // 0.5 * DENOMINATOR
        minErc20UniV3CapitalRatioDeviationD: BigNumber.from(10).pow(8),
        minErc20TokenRatioDeviationD: BigNumber.from(10).pow(8).div(2),
        minUniV3LiquidityRatioDeviationD: BigNumber.from(10).pow(8).div(2),
    });

    await lStrategy.updateOtherParams({
        minToken0ForOpening: BigNumber.from(10).pow(6),
        minToken1ForOpening: BigNumber.from(10).pow(6),
        rebalanceDeadline: BigNumber.from(86400 * 30),
    });
    log("Transferring ownership to lStrategyAdmin");

    const ADMIN_ROLE =
        "0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8"; // keccak256("admin)
    const ADMIN_DELEGATE_ROLE =
        "0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7"; // keccak256("admin_delegate")
    const OPERATOR_ROLE =
        "0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622"; // keccak256("operator")

    await lStrategy.grantRole(ADMIN_ROLE, mStrategyAdmin);
    await lStrategy.grantRole(ADMIN_DELEGATE_ROLE, mStrategyAdmin);
    await lStrategy.grantRole(ADMIN_DELEGATE_ROLE, deployer);
    await lStrategy.grantRole(OPERATOR_ROLE, mStrategyAdmin);
    await lStrategy.revokeRole(OPERATOR_ROLE, deployer);
    await lStrategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
    await lStrategy.revokeRole(ADMIN_ROLE, deployer);
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
