import { expect } from "chai";
import {
    ethers,
    deployments,
    getNamedAccounts,
    getExternalContract,
} from "hardhat";
import { now, sleepTo, withSigner } from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import {
    DelayedProtocolParamsStruct,
    DelayedStrategyParamsStruct,
} from "./types/YearnVaultGovernance";
import { BigNumber } from "@ethersproject/bignumber";
import { F } from "ramda";
import { Contract } from "@ethersproject/contracts";
import { read } from "fs";

describe("YearnVault", () => {
    let deploymentFixture: Function;
    let deployer: string;
    let admin: string;
    let stranger: string;
    let yearnVaultRegistry: string;
    let protocolGovernance: string;
    let vaultRegistry: string;
    let yearnVaultGovernance: string;
    let startTimestamp: number;
    let yearnVault: Contract;
    let nft: number;
    let vaultOwner: string;
    let tokens: string[];

    before(async () => {
        const {
            deployer: d,
            admin: a,
            yearnVaultRegistry: y,
            stranger: s,
        } = await getNamedAccounts();
        [deployer, admin, yearnVaultRegistry, stranger] = [d, a, y, s];

        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();

            const { execute, get, read } = deployments;
            protocolGovernance = (await get("ProtocolGovernance")).address;
            vaultRegistry = (await get("VaultRegistry")).address;
            yearnVaultGovernance = (await get("YearnVaultGovernance")).address;
            const { weth, usdc, test } = await getNamedAccounts();
            vaultOwner = test;
            tokens = [weth, usdc].map((t) => t.toLowerCase()).sort();
            await execute(
                "YearnVaultGovernance",
                {
                    from: deployer,
                    autoMine: true,
                },
                "deployVault",
                tokens,
                yearnVaultGovernance,
                vaultOwner
            );
            nft = (await read("VaultRegistry", "vaultsCount")).toNumber();
            const address = await read("VaultRegistry", "vaultForNft", nft);

            const usdcContract = await getExternalContract("usdc");
            const wethContract = await getExternalContract("weth");
            yearnVault = await ethers.getContractAt("YearnVault", address);

            await withSigner(vaultOwner, async (s) => {
                await usdcContract
                    .connect(s)
                    .approve(yearnVault.address, ethers.constants.MaxUint256);
                await wethContract
                    .connect(s)
                    .approve(yearnVault.address, ethers.constants.MaxUint256);
            });
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
        startTimestamp = now();
        await sleepTo(startTimestamp);
    });

    describe("tvl", () => {
        it("retuns cached tvl", async () => {
            const amounts = [1000, 2000];
            const usdcContract = await getExternalContract("usdc");
            const wethContract = await getExternalContract("weth");
            console.log(vaultOwner, tokens);

            console.log(
                "---",
                (await usdcContract.balanceOf(vaultOwner)).toString()
            );
            console.log(
                "+++",
                (await wethContract.balanceOf(vaultOwner)).toString()
            );
            console.log(
                "---",
                (
                    await usdcContract.allowance(vaultOwner, yearnVault.address)
                ).toString()
            );
            console.log(
                "+++",
                (
                    await wethContract.allowance(vaultOwner, yearnVault.address)
                ).toString()
            );

            await withSigner(vaultOwner, async (s) => {
                await yearnVault
                    .connect(s)
                    .transferAndPush(vaultOwner, tokens, amounts, []);
            });

            expect(await yearnVault.tvl()).to.eql(amounts);
        });
    });
});
