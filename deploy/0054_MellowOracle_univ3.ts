import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";
import { ALL_NETWORKS, MAIN_NETWORKS } from "./0000_utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get, read, execute } = deployments;
    const { deployer } = await getNamedAccounts();
    const { address: chainlinkOracle } = await get("ChainlinkOracle");
    const { address: univ3Oracle } = await get("UniV3Oracle");
    await deploy("MellowOracle", {
        from: deployer,
        args: [hre.ethers.constants.AddressZero, univ3Oracle, chainlinkOracle],
        log: true,
        autoMine: true,
    });
};
export default func;
func.tags = [
    "MellowOracle",
    "core",
    ...MAIN_NETWORKS,
    "polygon",
    "arbitrum",
    "optimism",
];
