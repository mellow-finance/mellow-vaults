import { PopulatedTransaction } from "@ethersproject/contracts";
import { TransactionReceipt } from "@ethersproject/abstract-provider";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

export async function sendTx(
    hre: HardhatRuntimeEnvironment,
    tx: PopulatedTransaction
): Promise<TransactionReceipt> {
    console.log("Sending transaction to the pool...");

    const [operator] = await hre.ethers.getSigners();
    const txResp = await operator.sendTransaction(tx);
    console.log(
        `Sent transaction with hash \`${txResp.hash}\`. Waiting confirmation`
    );
    const wait =
        hre.network.name == "hardhat" || hre.network.name == "localhost"
            ? undefined
            : 2;
    const receipt = await txResp.wait(wait);
    console.log("Transaction confirmed");
    return receipt;
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    await deploy("ProtocolGovernance", {
        from: deployer,
        args: [deployer],
        log: true,
        autoMine: true,
    });
};
export default func;
