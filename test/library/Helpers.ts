import { Contract } from "ethers";
import { network, ethers, getNamedAccounts } from "hardhat";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { filter, fromPairs, keys, KeyValuePair, map, pipe } from "ramda";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { randomBytes } from "crypto";

export const randomAddress = () => {
    const id = randomBytes(32).toString("hex");
    const privateKey = "0x" + id;
    const wallet = new ethers.Wallet(privateKey);
    return wallet.address;
};

export const toObject = (obj: any) =>
    pipe(
        keys,
        filter((x: string) => isNaN(parseInt(x))),
        map((x) => [x, obj[x]] as KeyValuePair<string, any>),
        fromPairs
    )(obj);

export const sleepTo = async (timestamp: BigNumberish) => {
    await network.provider.send("evm_setNextBlockTimestamp", [
        BigNumber.from(timestamp).toNumber(),
    ]);
    await network.provider.send("evm_mine");
};

export const sleep = async (seconds: BigNumberish) => {
    await network.provider.send("evm_increaseTime", [
        BigNumber.from(seconds).toNumber(),
    ]);
    await network.provider.send("evm_mine");
};

export const now = () => {
    return Math.ceil(new Date().getTime() / 1000);
};

export const sortContractsByAddresses = (contracts: Contract[]) => {
    return contracts.sort((a, b) => {
        return compareAddresses(a.address, b.address);
    });
};

export const sortAddresses = (addresses: string[]) => {
    return addresses.sort((a, b) => {
        return compareAddresses(a, b);
    });
};

export const compareAddresses = (a: string, b: string) => {
    return parseInt(
        (BigNumber.from(a).toBigInt() - BigNumber.from(b).toBigInt()).toString()
    );
};

export const encodeToBytes = (
    types: string[],
    objectToEncode: readonly any[]
) => {
    let toBytes = new ethers.utils.AbiCoder();
    return toBytes.encode(types, objectToEncode);
};

export const decodeFromBytes = (types: string[], bytesToDecode: string) => {
    let fromBytes = new ethers.utils.AbiCoder();
    return fromBytes.decode(types, bytesToDecode);
};

export const withSigner = async (
    address: string,
    f: (signer: SignerWithAddress) => Promise<void>
) => {
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
    });
    await network.provider.send("hardhat_setBalance", [
        address,
        "0x1000000000000000000",
    ]);
    const signer = await ethers.getSigner(address);
    await f(signer);
    await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [address],
    });
};

export async function depositW9(receiver: string, amount: BigNumberish) {
    const { weth } = await getNamedAccounts();
    const w9 = await ethers.getContractAt("WERC20Test", weth);
    const sender = randomAddress();
    await withSigner(sender, async (signer) => {
        await w9.connect(signer).deposit({ value: amount });
        await w9.connect(signer).transfer(receiver, amount);
    });
}
