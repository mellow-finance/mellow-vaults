import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "hardhat-deploy";

// struct InternalParams {
//     IProtocolGovernance protocolGovernance;
//     IVaultRegistry registry;
//     IVaultFactory factory;
// }

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, get } = deployments;
    const protocolGovernance = await get("ProtocolGovernance");
    const { deployer } = await getNamedAccounts();
    await deploy("VaultRegistry", {
        from: deployer,
        args: ["Mellow Vault Registry", "MVR", protocolGovernance.address],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};
export default func;
func.tags = ["ProtocolGovernance", "Vaults"];
