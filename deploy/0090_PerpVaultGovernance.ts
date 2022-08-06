import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { BigNumber } from "ethers";
import {ALL_NETWORKS, MAIN_NETWORKS, TRANSACTION_GAS_LIMITS} from "./0000_utils";
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, getChainId } = hre;
    const { deploy, get, log, execute, read } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, perpVault, accountBalance, clearingHouse, vusdcAddress, usdc, uniswapV3Factory} = await getNamedAccounts();

    const { address: singleton } = await deploy("PerpFuturesVault", {
        from: deployer,
        args: [],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
    const chainId = await getChainId();
    const hardhatChainId = "31337";
    if (chainId == hardhatChainId) {
        await deploy("PerpLPVault", { //mock deploy
            from: deployer,
            args: [],
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS
        });
    }
    await deploy("PerpVaultGovernance", {
        from: deployer,
        args: [
            {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
                singleton,
            },
            {
                vault: perpVault,
                clearingHouse: clearingHouse,
                accountBalance: accountBalance,
                vusdcAddress: vusdcAddress,
                usdcAddress: usdc,
                uniV3FactoryAddress: uniswapV3Factory,
                maxProtocolLeverage: 10
            },
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS
    });
};
export default func;
func.tags = [
    "PerpVaultGovernance",
    "core",
    ...MAIN_NETWORKS,
    "avalanche",
    "polygon",
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
