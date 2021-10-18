import { Contract } from "ethers";
import { network } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";

export const sleepTo = async (timestamp: number) => {
    await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
    await network.provider.send('evm_mine');
}

export const sleep = async (seconds: number) => {
    await network.provider.send("evm_increaseTime", [seconds]);
    await network.provider.send("evm_mine");
}

export const sortContractsByAddresses = (contracts: Contract[]) => {
    return contracts.sort((a, b) => {
        return parseInt((
            BigNumber.from(a.address).toBigInt() 
            - BigNumber.from(b.address).toBigInt()
        ).toString());
    });
}
