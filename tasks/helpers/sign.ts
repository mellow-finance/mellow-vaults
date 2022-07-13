import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { HardhatRuntimeEnvironment, Network } from "hardhat/types";


export const addSigner = async (
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

export const withSigner = async (
    hre: HardhatRuntimeEnvironment,
    address: string,
    f: (signer: SignerWithAddress) => Promise<void>
) => {
    const signer = await addSigner(hre, address);
    await f(signer);
    await removeSigner(hre.network, address);
};

export const removeSigner = async (network: Network, address: string) => {
    await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [address],
    });
};
