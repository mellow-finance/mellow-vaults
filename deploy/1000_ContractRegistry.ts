import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS, TRANSACTION_GAS_LIMITS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, execute } = deployments;
    const { deployer } = await getNamedAccounts();
    const protocolGovernance = await get("ProtocolGovernance");
    await deploy("ContractRegistry", {
        from: deployer,
        args: [protocolGovernance.address],
        log: true,
        autoMine: true,
    });
    const contractRegistry = await ethers.getContract("ContractRegistry");

    const vaultRegistry = await get("VaultRegistry");
    const chainlinkOracle = await get("ChainlinkOracle");
    const uniV3Oracle = await get("UniV3Oracle");
    const uniV2Oracle = await get("UniV2Oracle");
    const mellowOracle_univ3 = await get("MellowOracle");
    const aaveVaultGovernance = await get("AaveVaultGovernance");
    const uniV3VaultGovernance = await get("UniV3VaultGovernance");
    const erc20VaultGovernance = await get("ERC20VaultGovernance");
    const erc20RootVaultGovernance = await get("ERC20RootVaultGovernance");
    const yearnVaultGovernance = await get("YearnVaultGovernance");

    const multicallData = [
        contractRegistry.interface.encodeFunctionData("registerContract", [
            contractRegistry.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            protocolGovernance.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            vaultRegistry.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            chainlinkOracle.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            uniV3Oracle.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            uniV2Oracle.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            mellowOracle_univ3.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            aaveVaultGovernance.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            uniV3VaultGovernance.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            erc20VaultGovernance.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            erc20RootVaultGovernance.address,
        ]),
        contractRegistry.interface.encodeFunctionData("registerContract", [
            yearnVaultGovernance.address,
        ]),
    ];

    await execute(
        "ContractRegistry",
        {
            from: deployer,
            autoMine: true,
            log: true,
            ...TRANSACTION_GAS_LIMITS,
        },
        "multicall",
        multicallData
    );
};
export default func;
func.tags = ["ContractRegistry", "core", "mainnet"];
func.dependencies = [
    "ProtocolGovernance",
    "VaultRegistry",
    "ChainlinkOracle",
    "UniV3Oracle",
    "UniV2Oracle",
    "MellowOracle",
    "AaveVaultGovernance",
    "UniV3VaultGovernance",
    "ERC20VaultGovernance",
    "ERC20RootVaultGovernance",
    "YearnVaultGovernance",
];
