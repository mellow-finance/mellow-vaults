import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import {
    ALL_NETWORKS,
    MAIN_NETWORKS,
    TRANSACTION_GAS_LIMITS,
} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer, admin } =
        await getNamedAccounts();

    const pools = [
        "0x4641377ba87c2640B4f8D2EEcCE1F5c20048f7ed"
    ];

    await deploy("PancakeV3Oracle", {
        from: deployer,
        args: [
            "0x0bfbcf9fa4f9c56b0f40a671ad40e0805a091865",
            pools,
            admin
        ],
        log: true,
        autoMine: true,
        ...TRANSACTION_GAS_LIMITS,
    });
};
export default func;
func.tags = [
    "PancakeV3Oracle",
    "core",
    ...ALL_NETWORKS,
];
