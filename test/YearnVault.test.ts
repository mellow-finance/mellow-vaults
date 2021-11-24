import { assert, expect } from "chai";
import {
    ethers,
    deployments,
    getNamedAccounts,
    getExternalContract,
} from "hardhat";
import { now, sleepTo, withSigner } from "./library/Helpers";
import { BigNumber } from "@ethersproject/bignumber";
import { Contract } from "@ethersproject/contracts";
import { equals } from "ramda";

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
            const { weth, usdc, wbtc, test } = await getNamedAccounts();
            vaultOwner = test;
            tokens = [weth, usdc, wbtc].map((t) => t.toLowerCase()).sort();
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

            const contracts: Contract[] = [];
            for (const token of tokens) {
                contracts.push(await getExternalContract(token));
            }
            yearnVault = await ethers.getContractAt("YearnVault", address);

            await withSigner(vaultOwner, async (s) => {
                for (const contract of contracts) {
                    await contract
                        .connect(s)
                        .approve(
                            yearnVault.address,
                            ethers.constants.MaxUint256
                        );
                }
            });
        });
    });

    beforeEach(async () => {
        await deploymentFixture();
        startTimestamp =
            (await ethers.provider.getBlock("latest")).timestamp + 1000;
        await sleepTo(startTimestamp);
    });

    describe("tvl", () => {
        it("retuns cached tvl", async () => {
            const amounts = [1000, 2000, 3000];
            await withSigner(vaultOwner, async (s) => {
                await yearnVault
                    .connect(s)
                    .transferAndPush(vaultOwner, tokens, amounts, []);
            });

            expect(
                (await yearnVault.tvl()).map((x: BigNumber) => x.toNumber())
            ).to.eql(amounts.map((x: number) => x - 1));
        });

        describe("when no deposits are made", () => {
            it("returns 0", async () => {
                expect(
                    (await yearnVault.tvl()).map((x: BigNumber) => x.toNumber())
                ).to.eql([0, 0, 0]);
            });
        });
    });

    describe("push", () => {
        let yTokenContracts: Contract[];
        beforeEach(async () => {
            assert(
                equals(
                    (await yearnVault.tvl()).map((x: any) => x.toNumber()),
                    [0, 0, 0]
                ),
                "Zero TVL"
            );
            const yTokens = await yearnVault.yTokens();
            yTokenContracts = [];
            for (const yToken of yTokens) {
                const contract = await ethers.getContractAt("LpIssuer", yToken); // just use ERC20 interface here
                yTokenContracts.push(contract);
                assert(
                    (
                        await contract.balanceOf(yearnVault.address)
                    ).toNumber() === 0,
                    "Zero balance"
                );
            }
        });
        it("pushes tokens into yearn", async () => {
            const amounts = [1000, 2000, 3000];
            await withSigner(vaultOwner, async (s) => {
                await yearnVault
                    .connect(s)
                    .transferAndPush(vaultOwner, tokens, amounts, []);
            });
            for (const yToken of yTokenContracts) {
                const balance = await yToken.balanceOf(yearnVault.address);
                expect(balance.toNumber()).to.gt(0);
            }
            const tvls = (await yearnVault.tvl()).map((x: BigNumber) =>
                x.toNumber()
            );
            for (const tvl of tvls) {
                expect(tvl).to.gt(0);
            }
        });

        describe("when one of pushed tokens equals 0", () => {
            it("doesn't push that token", async () => {
                const amounts = [1000, 0, 3000];
                await withSigner(vaultOwner, async (s) => {
                    await yearnVault
                        .connect(s)
                        .transferAndPush(vaultOwner, tokens, amounts, []);
                });
                const balance = await yTokenContracts[1].balanceOf(
                    yearnVault.address
                );
                expect(balance.toNumber()).to.eq(0);
                const tvls = (await yearnVault.tvl()).map((x: BigNumber) =>
                    x.toNumber()
                );
                expect(tvls[1]).to.eq(0);
            });
        });

        describe("when pushed twice", () => {
            it("succeeds", async () => {
                const amounts = [1000, 2000, 3000];
                await withSigner(vaultOwner, async (s) => {
                    await yearnVault
                        .connect(s)
                        .transferAndPush(vaultOwner, tokens, amounts, []);
                });
                await withSigner(vaultOwner, async (s) => {
                    await yearnVault
                        .connect(s)
                        .transferAndPush(vaultOwner, tokens, amounts, []);
                });

                for (const yToken of yTokenContracts) {
                    const balance = await yToken.balanceOf(yearnVault.address);
                    expect(balance.toNumber()).to.gt(0);
                }
                const tvls = (await yearnVault.tvl()).map((x: BigNumber) =>
                    x.toNumber()
                );
                for (const tvl of tvls) {
                    expect(tvl).to.gt(0);
                }
            });
        });
    });
});
