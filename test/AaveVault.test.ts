import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, AaveVault } from "./types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import {
    AAVE_VAULT_INTERFACE_ID,
    INTEGRATION_VAULT_INTERFACE_ID,
} from "./library/Constants";
import Exceptions from "./library/Exceptions";
import { timeStamp } from "console";
import { uint256 } from "./library/property";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<AaveVault, DeployOptions, CustomContext>("AaveVault", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read, deploy } = deployments;

                const { curveRouter, deployer } = await getNamedAccounts();
                this.curveRouter = curveRouter;
                this.preparePush = async () => {
                    await sleep(0);
                };

                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                this.aUsdc = await ethers.getContractAt(
                    "ERC20Token",
                    "0xbcca60bb61934080951369a648fb03df4f96263c" // aUSDC address
                );
                this.aWeth = await ethers.getContractAt(
                    "ERC20Token",
                    "0x030ba81f1c18d280636f32af80b9aad02cf0854e" // aWETH address
                );

                let aaveVaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                await setupVault(hre, aaveVaultNft, "AaveVaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, aaveVaultNft],
                    this.deployer.address,
                    this.deployer.address
                );
                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const aaveVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    aaveVaultNft
                );
                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.subject = await ethers.getContractAt(
                    "AaveVault",
                    aaveVault
                );

                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

                for (let address of [
                    this.deployer.address,
                    this.subject.address,
                    this.erc20Vault.address,
                ]) {
                    await mint(
                        "USDC",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await mint(
                        "WETH",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await this.weth.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                }

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#tvl", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
                await this.usdc
                    .connect(signer)
                    .approve(
                        this.deployer.address,
                        ethers.constants.MaxUint256
                    );
                await this.weth
                    .connect(signer)
                    .approve(
                        this.deployer.address,
                        ethers.constants.MaxUint256
                    );

                await this.usdc
                    .connect(signer)
                    .transfer(
                        this.deployer.address,
                        await this.usdc.balanceOf(this.subject.address)
                    );
                await this.weth
                    .connect(signer)
                    .transfer(
                        this.deployer.address,
                        await this.weth.balanceOf(this.subject.address)
                    );
            });
        });

        it("returns total value locked", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(18).mul(3000)
            );
            await mint(
                "WETH",
                this.subject.address,
                BigNumber.from(10).pow(18).mul(3000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                encodeToBytes(["uint256"], [BigNumber.from(1)])
            );
            const result = await this.subject.tvl();
            for (let amountsId = 0; amountsId < 2; ++amountsId) {
                for (let tokenId = 0; tokenId < 2; ++tokenId) {
                    expect(result[amountsId][tokenId]).gt(0);
                }
            }
        });

        it("returns total value locked, no time passed from initialization", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(18).mul(3000)
            );
            await mint(
                "WETH",
                this.subject.address,
                BigNumber.from(10).pow(18).mul(3000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                encodeToBytes(["uint256"], [BigNumber.from(1)])
            );
            const { timestamp } = await ethers.provider.getBlock("latest");
            await ethers.provider.send("hardhat_setStorageAt", [
                this.subject.address,
                "0x8", // address of _lastTvlUpdateTimestamp
                encodeToBytes(["uint256"], [BigNumber.from(timestamp)]),
            ]);
            const result = await this.subject.tvl();
            for (let amountsId = 0; amountsId < 2; ++amountsId) {
                for (let tokenId = 0; tokenId < 2; ++tokenId) {
                    expect(result[amountsId][tokenId]).gt(0);
                }
            }
        });

        describe("edge cases:", () => {
            describe("when there are no initial funds", () => {
                it("returns zeroes", async () => {
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        for (let tokenId = 0; tokenId < 2; ++tokenId) {
                            expect(result[amountsId][tokenId]).eq(0);
                        }
                    }
                });
            });
        });
    });

    describe("#lendingPool", () => {
        it("returns ILendingPool", async () => {
            const { aaveLendingPool } = await getNamedAccounts();
            expect(await this.subject.lendingPool()).to.be.equal(
                aaveLendingPool
            );
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(this.subject.connect(s).lendingPool()).to.not
                        .be.reverted;
                });
            });
        });
    });

    describe("#updateTvls", () => {
        it("updates total value locked", async () => {
            await this.subject.push(
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                []
            );
            await withSigner(this.subject.address, async (signer) => {
                for (let token of [this.aUsdc, this.aWeth]) {
                    await token
                        .connect(signer)
                        .approve(
                            this.deployer.address,
                            ethers.constants.MaxUint256
                        );
                    await token
                        .connect(signer)
                        .transfer(
                            this.deployer.address,
                            await token.balanceOf(signer.address)
                        );
                }
            });
            await this.subject.updateTvls();
            const oldTvls = await this.subject.tvl();
            await this.aUsdc.approve(
                this.subject.address,
                ethers.constants.MaxUint256
            );
            await this.aUsdc.transfer(
                this.subject.address,
                BigNumber.from(10).pow(6).mul(3000)
            );
            expect(await this.subject.tvl()).to.be.deep.equal(oldTvls);
            await this.subject.updateTvls();
            const newTvls = await this.subject.tvl();
            for (let amountsId = 0; amountsId < 2; ++amountsId) {
                expect(newTvls[amountsId][0].sub(oldTvls[amountsId][0])).gte(
                    BigNumber.from(10).pow(6).mul(3000)
                );
            }
        });
    });

    describe("#initialize", () => {
        beforeEach(async () => {
            this.nft = await ethers.provider.send("eth_getStorageAt", [
                this.subject.address,
                "0x4", // address of _nft
            ]);
            await ethers.provider.send("hardhat_setStorageAt", [
                this.subject.address,
                "0x4", // address of _nft
                "0x0000000000000000000000000000000000000000000000000000000000000000",
            ]);
        });

        it("emits Initialized event", async () => {
            await withSigner(
                this.aaveVaultGovernance.address,
                async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .initialize(this.nft, [
                                this.usdc.address,
                                this.weth.address,
                            ])
                    ).to.emit(this.subject, "Initialized");
                }
            );
        });
        it("initializes contract successfully", async () => {
            await withSigner(
                this.aaveVaultGovernance.address,
                async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .initialize(this.nft, [
                                this.usdc.address,
                                this.weth.address,
                            ])
                    ).to.not.be.reverted;
                }
            );
        });

        describe("edge cases:", () => {
            describe("when vault's nft is not 0", () => {
                it(`reverts with ${Exceptions.INIT}`, async () => {
                    await ethers.provider.send("hardhat_setStorageAt", [
                        this.subject.address,
                        "0x4", // address of _nft
                        "0x0000000000000000000000000000000000000000000000000000000000000007",
                    ]);
                    await expect(
                        this.subject.initialize(this.nft, [
                            this.usdc.address,
                            this.weth.address,
                        ])
                    ).to.be.revertedWith(Exceptions.INIT);
                });
            });
            describe("when tokens are not sorted", () => {
                it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                    await expect(
                        this.subject.initialize(this.nft, [
                            this.weth.address,
                            this.usdc.address,
                        ])
                    ).to.be.revertedWith(Exceptions.INVARIANT);
                });
            });
            describe("when tokens are not unique", () => {
                it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                    await expect(
                        this.subject.initialize(this.nft, [
                            this.weth.address,
                            this.weth.address,
                        ])
                    ).to.be.revertedWith(Exceptions.INVARIANT);
                });
            });
            describe("when setting zero nft", () => {
                it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                    await expect(
                        this.subject.initialize(0, [
                            this.usdc.address,
                            this.weth.address,
                        ])
                    ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                });
            });
            describe("when setting token with address zero", () => {
                it(`reverts with ${Exceptions.ADDRESS_ZERO}`, async () => {
                    let erc20Factory = await ethers.getContractFactory(
                        "ERC20Token"
                    );
                    let unlistedToken  = await erc20Factory.deploy();
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(unlistedToken.address, [
                            PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    await withSigner(
                        this.aaveVaultGovernance.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                .connect(signer)
                                .initialize(this.nft, [
                                    unlistedToken.address
                                ])
                            ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                        }
                    );
                });
            });
            describe("when token has no permission to become a vault token", () => {
                it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                    await this.protocolGovernance
                        .connect(this.admin)
                        .revokePermissions(this.usdc.address, [
                            PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                        ]);
                    await withSigner(
                        this.aaveVaultGovernance.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .initialize(this.nft, [
                                        this.usdc.address,
                                        this.weth.address,
                                    ])
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        }
                    );
                });
            });
        });
    });

    describe("#supportsInterface", () => {
        it(`returns true if this contract supports ${AAVE_VAULT_INTERFACE_ID} interface`, async () => {
            expect(
                await this.subject.supportsInterface(AAVE_VAULT_INTERFACE_ID)
            ).to.be.true;
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .supportsInterface(INTEGRATION_VAULT_INTERFACE_ID)
                    ).to.not.be.reverted;
                });
            });
        });
    });

    integrationVaultBehavior.call(this, {});
});
