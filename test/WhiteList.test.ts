import hre from "hardhat";
import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, withSigner, randomAddress } from "./library/Helpers";
import { contract } from "./library/setup";
import { WhiteList, ERC20RootVault } from "./types";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import { MerkleTree } from "merkletreejs";
import keccak256 = require("keccak256");
import { BytesLike } from "ethers";

type CustomContext = {
    erc20RootVault: ERC20RootVault;
    addresses: string[];
};

type DeployOptions = {};

contract<WhiteList, DeployOptions, CustomContext>("WhiteList", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { deploy, read } = deployments;

                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const erc20VaultNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft],
                    this.deployer.address,
                    this.deployer.address
                );

                const erc20RootVaultAddress = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
                );
                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVaultAddress
                );

                const { address } = await deploy("WhiteList", {
                    from: this.deployer.address,
                    args: [this.admin.address],
                    log: true,
                    autoMine: true,
                });

                this.subject = await ethers.getContractAt("WhiteList", address);

                this.addresses = [];
                for (let i = 0; i < 3; ++i) {
                    this.addresses.push(randomAddress());
                }

                await mint(
                    "USDC",
                    this.admin.address,
                    BigNumber.from(10).pow(4)
                );
                await mint(
                    "WETH",
                    this.admin.address,
                    BigNumber.from(10).pow(10)
                );
                await this.weth
                    .connect(this.admin)
                    .approve(
                        this.erc20RootVault.address,
                        ethers.constants.MaxUint256
                    );
                await this.usdc
                    .connect(this.admin)
                    .approve(
                        this.erc20RootVault.address,
                        ethers.constants.MaxUint256
                    );
                await this.erc20RootVault
                    .connect(this.admin)
                    .deposit(
                        [BigNumber.from(10).pow(4), BigNumber.from(10).pow(10)],
                        0,
                        []
                    );

                for (let address of this.addresses) {
                    await mint(
                        "USDC",
                        address,
                        BigNumber.from(10).pow(6).mul(30)
                    );
                    await mint(
                        "WETH",
                        address,
                        BigNumber.from(10).pow(18).mul(30)
                    );
                    await withSigner(address, async (signer) => {
                        await this.usdc
                            .connect(signer)
                            .approve(
                                this.erc20RootVault.address,
                                ethers.constants.MaxUint256
                            );
                        await this.weth
                            .connect(signer)
                            .approve(
                                this.erc20RootVault.address,
                                ethers.constants.MaxUint256
                            );
                        await this.usdc
                            .connect(signer)
                            .approve(
                                this.subject.address,
                                ethers.constants.MaxUint256
                            );
                        await this.weth
                            .connect(signer)
                            .approve(
                                this.subject.address,
                                ethers.constants.MaxUint256
                            );
                    });
                }

                this.usualDepositAvailable = async (
                    vault: ERC20RootVault,
                    depositorAddress: string
                ) => {
                    const allDepositors = await vault.depositorsAllowlist();
                    for (let elem in allDepositors) {
                        if (elem == depositorAddress) {
                            return true;
                        }
                    }
                    return false;
                };

                this.getWhitelistForVault = async (vault: ERC20RootVault) => {
                    // For now we use constant address
                    // actual example:
                    // https://api.mellow.finance/verifier/0x78ba57594656400d74a0c5ea80f84750cb47f449?chain=mainnet
                    return this.subject.address;
                };

                this.getProof = async (
                    whitelistAddress: string,
                    depositorAddress: string
                ) => {
                    // For now we use constant proofs
                    // actual example:
                    // https://api.mellow.finance/proof/0xa96eB894266a9CB08d64867C1365E9f1157D5B68/0x9a3CB5A473e1055a014B9aE4bc63C21BBb8b82B3?chain=mainnet
                    let tree = new MerkleTree(
                        this.addresses.map((x) => keccak256(x)),
                        keccak256,
                        { sortPairs: true }
                    );
                    return tree.getHexProof(keccak256(depositorAddress));
                };

                this.proxyDepositAvailable = async (
                    vault: ERC20RootVault,
                    depositorAddress: string
                ) => {
                    const whitlistAddres = await this.getWhitelistForVault(
                        vault
                    );
                    if (!whitlistAddres) {
                        return false;
                    }
                    const proof = await this.getProof(
                        whitlistAddres,
                        depositorAddress
                    );
                    return proof.length != 0;
                };

                this.depositViaWhitelist = async (
                    vaultAddress: string,
                    amounts: BigNumber[],
                    minLpAmount: BigNumber,
                    options: BytesLike,
                    whitelist: WhiteList,
                    depositorAddress: string
                ) => {
                    const proof = await this.getProof(
                        whitelist.address,
                        depositorAddress
                    );
                    return await whitelist.deposit(
                        vaultAddress,
                        amounts,
                        minLpAmount,
                        options,
                        proof
                    );
                };

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#deposit", () => {
        beforeEach(async () => {
            this.erc20RootVault
                .connect(this.admin)
                .addDepositorsToAllowlist([this.subject.address]);
        });

        it("works correctly", async () => {
            let tree = new MerkleTree(
                this.addresses.map((x) => keccak256(x)),
                keccak256,
                { sortPairs: true }
            );
            await this.subject
                .connect(this.admin)
                .updateRoot("0x" + tree.getRoot().toString("hex"));
            for (let address of this.addresses) {
                const proof = tree.getHexProof(keccak256(address));
                await withSigner(address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .deposit(
                                this.erc20RootVault.address,
                                [
                                    BigNumber.from(10).pow(6),
                                    BigNumber.from(10).pow(18),
                                ],
                                0,
                                [],
                                proof
                            )
                    ).not.to.be.reverted;
                });
            }
        });

        it("reverts on wrong address", async () => {
            let tree = new MerkleTree(
                this.addresses.map((x) => keccak256(x)),
                keccak256,
                { sortPairs: true }
            );
            await this.subject
                .connect(this.admin)
                .updateRoot("0x" + tree.getRoot().toString("hex"));
            const address = randomAddress();
            const proof = tree.getHexProof(keccak256(address));
            await withSigner(address, async (signer) => {
                await expect(
                    this.subject
                        .connect(signer)
                        .deposit(
                            this.erc20RootVault.address,
                            [
                                BigNumber.from(10).pow(6),
                                BigNumber.from(10).pow(18),
                            ],
                            0,
                            [],
                            proof
                        )
                ).to.be.revertedWith("FRB");
            });
        });
    });
});
