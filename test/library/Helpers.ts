import { Contract, Signer, PopulatedTransaction } from "ethers";
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
import { ProtocolGovernance } from "./Types";
import { Address } from "hardhat-deploy/dist/types";
import {
    IVault,
    IVaultGovernance,
    UniV3VaultGovernance,
    GatewayVaultGovernance,
    VaultRegistry,
    ERC20,
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

export const addSigner = async (
    address: string
): Promise<SignerWithAddress> => {
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

export type MintableToken = "USDC" | "WETH" | "WBTC";

export const mint = async (
    token: MintableToken | string,
    to: string,
    amount: BigNumberish
) => {
    const { wbtc, weth, usdc } = await getNamedAccounts();
    switch (token.toLowerCase()) {
        case wbtc.toLowerCase():
            token = "WBTC";
            break;
        case weth.toLowerCase():
            token = "WETH";
            break;
        case usdc.toLowerCase():
            token = "USDC";
            break;

        default:
            break;
    }
    switch (token) {
        case "USDC":
            // masterMinter()
            let minter = await ethers.provider.call({
                to: usdc,
                data: `0x35d99f35`,
            });
            minter = `0x${minter.substring(2 + 12 * 2)}`;
            await withSigner(minter, async (s) => {
                // function configureMinter(address minter, uint256 minterAllowedAmount)
                let tx: PopulatedTransaction = {
                    to: usdc,
                    from: minter,
                    data: `0x4e44d956${ethers.utils
                        .hexZeroPad(s.address, 32)
                        .substring(2)}${ethers.utils
                        .hexZeroPad(BigNumber.from(amount).toHexString(), 32)
                        .substring(2)}`,
                    gasLimit: BigNumber.from(10 ** 6),
                };

                let resp = await s.sendTransaction(tx);
                await resp.wait();

                // function mint(address,uint256)
                tx = {
                    to: usdc,
                    from: minter,
                    data: `0x40c10f19${ethers.utils
                        .hexZeroPad(to, 32)
                        .substring(2)}${ethers.utils
                        .hexZeroPad(BigNumber.from(amount).toHexString(), 32)
                        .substring(2)}`,
                    gasLimit: BigNumber.from(10 ** 6),
                };

                resp = await s.sendTransaction(tx);
                await resp.wait();
            });
            break;

        case "WETH":
            const addr = randomAddress();
            await withSigner(addr, async (s) => {
                // deposit()
                const tx: PopulatedTransaction = {
                    to: weth,
                    from: addr,
                    data: `0xd0e30db0`,
                    gasLimit: BigNumber.from(10 ** 6),
                    value: BigNumber.from(amount),
                };
                const resp = await s.sendTransaction(tx);
                await resp.wait();
                const c: ERC20 = await ethers.getContractAt("ERC20", weth);
                await c.connect(s).transfer(to, amount);
            });
            break;
        case "WBTC":
            // owner()
            let owner = await ethers.provider.call({
                to: wbtc,
                data: `0x8da5cb5b`,
            });
            owner = `0x${owner.substring(2 + 12 * 2)}`;
            await withSigner(owner, async (s) => {
                // function mint(address,uint256)
                const tx = {
                    to: wbtc,
                    from: owner,
                    data: `0x40c10f19${ethers.utils
                        .hexZeroPad(to, 32)
                        .substring(2)}${ethers.utils
                        .hexZeroPad(BigNumber.from(amount).toHexString(), 32)
                        .substring(2)}`,
                    gasLimit: BigNumber.from(10 ** 6),
                };

                const resp = await s.sendTransaction(tx);
                await resp.wait();
            });
            break;

        default:
            throw `Unknown token: ${token}`;
    }
};
