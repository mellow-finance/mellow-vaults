import { Contract } from "ethers";
import { network, ethers } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { filter, fromPairs, keys, KeyValuePair, map, pipe } from "ramda";
import { utils } from "ethers";

export const toObject = (obj: any) =>
    pipe(
        keys,
        filter((x: string) => isNaN(parseInt(x))),
        map((x) => [x, obj[x]] as KeyValuePair<string, any>),
        fromPairs
    )(obj);

export const sleepTo = async (timestamp: number) => {
    await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
    await network.provider.send("evm_mine");
};

export const sleep = async (seconds: number) => {
    await network.provider.send("evm_increaseTime", [seconds]);
    await network.provider.send("evm_mine");
};

export const now = () => {
    return Math.ceil(new Date().getTime() / 1000);
};

export const sortContractsByAddresses = (contracts: Contract[]) => {
    return contracts.sort((a, b) => {
        return parseInt(
            (
                BigNumber.from(a.address).toBigInt() -
                BigNumber.from(b.address).toBigInt()
            ).toString()
        );
    });
};

export const encodeToBytes = (
    types: string[],
    objectToEncode: readonly any[]
) => {
    let toBytes = new utils.AbiCoder();
    return toBytes.encode(types, objectToEncode);
};

export const decodeFromBytes = (types: string[], bytesToDecode: string) => {
    let fromBytes = new utils.AbiCoder();
    return fromBytes.decode(types, bytesToDecode);
};
