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
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import {
    IVault,
    IVaultGovernance,
    UniV3VaultGovernance,
    VaultRegistry,
    ERC20Token as ERC20,
} from "../types";
import {
    DelayedProtocolPerVaultParamsStruct as ERC20RootVaultDelayedProtocolPerVaultParamsStruct,
    DelayedStrategyParamsStruct as ERC20RootVaultDelayedStrategyParamsStruct,
    StrategyParamsStruct as ERC20RootVaultStrategyParamsStruct,
    ERC20RootVaultGovernance,
} from "../types/ERC20RootVaultGovernance";

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

export async function approveERC20(
    token: string,
    spender: string
): Promise<void> {
    const tokenContract = await ethers.getContractAt("IERC20", token);
    await tokenContract.approve(spender, ethers.constants.MaxUint256);
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
          name: "ERC20RootVault";
          tokenName: string;
          tokenSymbol: string;
          strategy: string;
          subvaultNfts: BigNumberish[];
          strategyParams: ERC20RootVaultStrategyParamsStruct;
          delayedStrategyParams: ERC20RootVaultDelayedStrategyParamsStruct;
          delayedProtocolPerVaultParams: ERC20RootVaultDelayedProtocolPerVaultParamsStruct;
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
    let options: any[];
    switch (params.name) {
        case "UniV3Vault":
            options = [params.fee];
            break;
        case "ERC20RootVault":
            options = [
                params.strategy,
                params.subvaultNfts,
                params.tokenName,
                params.tokenSymbol,
            ];

        default:
            options = [];
            break;
    }
    // @ts-ignore
    await governance.createVault(
        ...[params.vaultTokens, ...options, params.nftOwner]
    );
    const vaultRegistry: VaultRegistry = await ethers.getContract(
        "VaultRegistry"
    );
    const nft = (await vaultRegistry.vaultsCount()).toNumber();
    const address = await vaultRegistry.vaultForNft(nft);
    switch (params.name) {
        case "ERC20RootVault":
            const gov: ERC20RootVaultGovernance = await ethers.getContract(
                "ERC20RootVaultGovernance"
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
                const c: ERC20 = await ethers.getContractAt("ERC20Token", weth);
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

export function zeroify<
    T extends BigNumber | string | number | { [key: string]: any }
>(x: T): T {
    if (x instanceof BigNumber) {
        return BigNumber.from(0) as T;
    }
    if (x instanceof Array) {
        return [] as unknown as T;
    }

    if (typeof x === "string") {
        if (x.startsWith("0x")) {
            return ethers.constants.AddressZero as T;
        }
    }
    if (typeof x === "number") {
        return 0 as T;
    }
    if (typeof x === "object") {
        const res: { [key: string]: any } = {};
        for (const key in x) {
            res[key] = zeroify(x[key]);
        }
        return res as T;
    }
    throw `Unknown type for value ${x}`;
}

export const randomNft = () => {
    return Math.round(Math.random() * 1000000 + 100);
};

export async function mintUniV3Position_USDC_WETH(options: {
    tickLower: BigNumberish;
    tickUpper: BigNumberish;
    usdcAmount: BigNumberish;
    wethAmount: BigNumberish;
    fee: 500 | 3000 | 10000;
}): Promise<any> {
    const { weth, usdc, deployer, uniswapV3PositionManager } =
        await getNamedAccounts();

    const wethContract = await ethers.getContractAt("ERC20Token", weth);
    const usdcContract = await ethers.getContractAt("ERC20Token", usdc);

    const positionManagerContract = await ethers.getContractAt(
        INonfungiblePositionManager,
        uniswapV3PositionManager
    );

    await mint("WETH", deployer, options.wethAmount);
    await mint("USDC", deployer, options.usdcAmount);

    if (
        (await wethContract.allowance(deployer, uniswapV3PositionManager)).eq(
            BigNumber.from(0)
        )
    ) {
        await wethContract.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
    }
    if (
        (await usdcContract.allowance(deployer, uniswapV3PositionManager)).eq(
            BigNumber.from(0)
        )
    ) {
        await usdcContract.approve(
            uniswapV3PositionManager,
            ethers.constants.MaxUint256
        );
    }

    const mintParams = {
        token0: usdc,
        token1: weth,
        fee: options.fee,
        tickLower: options.tickLower,
        tickUpper: options.tickUpper,
        amount0Desired: options.usdcAmount,
        amount1Desired: options.wethAmount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: deployer,
        deadline: ethers.constants.MaxUint256,
    };

    const result = await positionManagerContract.callStatic.mint(mintParams);
    await positionManagerContract.mint(mintParams);
    return result;
}
