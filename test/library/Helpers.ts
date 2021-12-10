import { Contract, Signer } from "ethers";
import { network, ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import {
    equals,
    filter,
    fromPairs,
    keys,
    KeyValuePair,
    map,
    pipe,
    prop,
} from "ramda";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { randomBytes } from "crypto";
import { ProtocolGovernance, ERC20 } from "./Types";
import { Address } from "hardhat-deploy/dist/types";
import {
    IVault,
    IVaultGovernance,
    UniV3VaultGovernance,
    GatewayVaultGovernance,
    VaultRegistry,
} from "../types";
import {
    DelayedStrategyParamsStruct as GatewayDelayedStrategyParamsStruct,
    StrategyParamsStruct as GatewayStrategyParamsStruct,
} from "../types/GatewayVaultGovernance";
import {
    DelayedProtocolPerVaultParamsStruct as LpIssuerDelayedProtocolPerVaultParamsStruct,
    DelayedStrategyParamsStruct as LpIssuerDelayedStrategyParamsStruct,
    StrategyParamsStruct as LpIssuerStrategyParamsStruct,
    LpIssuerGovernance,
} from "../types/LpIssuerGovernance";

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

const addSigner = async (address: string): Promise<SignerWithAddress> => {
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

const removeSigner = async (address: string) => {
    await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [address],
    });
};

export const setTokenWhitelist = async (
    protocolGovernance: ProtocolGovernance,
    tokens: ERC20[],
    admin: SignerWithAddress | Signer
) => {
    let allowedAddresses = new Array<Address>(tokens.length);
    for (var i = 0; i < tokens.length; ++i) {
        allowedAddresses[i] = tokens[i].address;
    }
    await protocolGovernance
        .connect(admin)
        .setPendingTokenWhitelistAdd(allowedAddresses);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await protocolGovernance.connect(admin).commitTokenWhitelistAdd();
};

export async function depositW9(
    receiver: string,
    amount: BigNumberish
): Promise<void> {
    const { weth } = await getNamedAccounts();
    const w9 = await ethers.getContractAt("WERC20Test", weth);
    const sender = randomAddress();
    await withSigner(sender, async (signer) => {
        await w9.connect(signer).deposit({ value: amount });
        await w9.connect(signer).transfer(receiver, amount);
    });
}

export async function depositWBTC(
    receiver: string,
    amount: BigNumberish
): Promise<void> {
    const { wbtcRichGuy, wbtc } = await getNamedAccounts();
    const wbtcContract = await ethers.getContractAt("WERC20Test", wbtc);
    await withSigner(wbtcRichGuy, async (signer) => {
        await wbtcContract.connect(signer).transfer(receiver, amount);
    });
}

export const withSigner = async (
    address: string,
    f: (signer: SignerWithAddress) => Promise<void>
) => {
    const signer = await addSigner(address);
    await f(signer);
    await removeSigner(address);
};

export type VaultParams =
    | { name: "AaveVault" }
    | { name: "YearnVault" }
    | { name: "ERC20Vault" }
    | { name: "UniV3Vault"; fee: BigNumberish }
    | {
          name: "GatewayVault";
          subvaultNfts: BigNumberish[];
          strategyParams: GatewayStrategyParamsStruct;
          delayedStrategyParams: GatewayDelayedStrategyParamsStruct;
      }
    | {
          name: "LpIssuer";
          tokenName: string;
          tokenSymbol: string;
          strategyParams: LpIssuerStrategyParamsStruct;
          delayedStrategyParams: LpIssuerDelayedStrategyParamsStruct;
          delayedProtocolPerVaultParams: LpIssuerDelayedProtocolPerVaultParamsStruct;
      };
export type BaseDeployParams = {
    vaultTokens: string[];
    nftOwner: string;
};

export const deployVault = async (
    params: VaultParams & BaseDeployParams
): Promise<{ nft: number; address: string }> => {
    const governance: IVaultGovernance = await ethers.getContract(
        `${params.name}Governance`
    );
    const coder = ethers.utils.defaultAbiCoder;
    let options;
    switch (params.name) {
        case "UniV3Vault":
            options = coder.encode(["uint256"], [params.fee]);
            break;
        case "GatewayVault":
            options = coder.encode(["uint256[]"], [params.subvaultNfts]);
            break;
        case "LpIssuer":
            options = coder.encode(
                ["string", "string"],
                [params.tokenName, params.tokenSymbol]
            );

        default:
            options = [];
            break;
    }
    await governance.deployVault(params.vaultTokens, options, params.nftOwner);
    const vaultRegistry: VaultRegistry = await ethers.getContract(
        "VaultRegistry"
    );
    const nft = (await vaultRegistry.vaultsCount()).toNumber();
    const address = await vaultRegistry.vaultForNft(nft);
    switch (params.name) {
        case "LpIssuer":
            const gov: LpIssuerGovernance = await ethers.getContract(
                "LpIssuerGovernance"
            );
            await gov.setStrategyParams(nft, params.strategyParams);
            await gov.stageDelayedStrategyParams(
                nft,
                params.delayedStrategyParams
            );
            await gov.commitDelayedStrategyParams(nft);
            await gov.stageDelayedProtocolPerVaultParams(
                nft,
                params.delayedProtocolPerVaultParams
            );
            await gov.commitDelayedProtocolPerVaultParams(nft);
            break;
        case "GatewayVault":
            const ggov: GatewayVaultGovernance = await ethers.getContract(
                "GatewayVaultGovernance"
            );
            await ggov.setStrategyParams(nft, params.strategyParams);
            await ggov.stageDelayedStrategyParams(
                nft,
                params.delayedStrategyParams
            );
            await ggov.commitDelayedStrategyParams(nft);
            break;
        default:
            break;
    }
    return { nft, address };
};
