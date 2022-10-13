import hre from "hardhat";
import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, withSigner, randomAddress, addSigner } from "./library/Helpers";
import { contract } from "./library/setup";
import { WhiteList, ERC20RootVault, ERC20Vault } from "./types";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import Exceptions from "./library/Exceptions";
import { MerkleTree } from "merkletreejs";
import keccak256 = require("keccak256");
import { min } from "ramda";

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
            // this.erc20RootVault
            //     .connect(this.admin)
            //     .al
        });

        it("works correctly", async () => {
            let tree = new MerkleTree(
                this.addresses.map((x) => keccak256(x)),
                keccak256,
                { sortPairs: true }
            );
            await this.subject
                .connect(this.admin)
                .updateVault(
                    this.erc20RootVault.address,
                    "0x" + tree.getRoot().toString("hex")
                );
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
                .updateVault(
                    this.erc20RootVault.address,
                    "0x" + tree.getRoot().toString("hex")
                );
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
