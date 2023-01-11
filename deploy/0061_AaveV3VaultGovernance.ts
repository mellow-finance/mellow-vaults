import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { BigNumber } from "ethers";
import { TRANSACTION_GAS_LIMITS} from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const vaultRegistry = await get("VaultRegistry");
    const { deployer, aaveV3Pool } = await getNamedAccounts();
    if (aaveV3Pool) {
        const { address: singleton } = await deploy("AaveV3Vault", {
            from: deployer,
            args: [],
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS
        });
        await deploy("AaveV3VaultGovernance", {
            from: deployer,
            args: [
                {
                    protocolGovernance: protocolGovernance.address,
                    registry: vaultRegistry.address,
                    singleton,
                },
                {
                    pool: aaveV3Pool,
                    estimatedAaveAPY: BigNumber.from(10).pow(9).div(100), // 1%
                },
            ],
            log: true,
            autoMine: true,
            ...TRANSACTION_GAS_LIMITS
        });
    }
};
export default func;
func.tags = [
    "AaveV3VaultGovernance",
    "core",
    "arbitrum",
    "polygon",
];
func.dependencies = ["ProtocolGovernance", "VaultRegistry"];
