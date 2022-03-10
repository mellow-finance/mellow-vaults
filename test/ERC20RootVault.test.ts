import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    withSigner,
    randomAddress,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, UniV3Vault } from "./types";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import Exceptions from "./library/Exceptions";
import {
    ERC20_ROOT_VAULT_INTERFACE_ID,
    YEARN_VAULT_INTERFACE_ID,
} from "./library/Constants";
import { randomInt } from "crypto";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "ERC20RootVault",
    function () {
        const uniV3PoolFee = 3000;

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { read } = deployments;

                    const { uniswapV3PositionManager, curveRouter } =
                        await getNamedAccounts();
                    this.curveRouter = curveRouter;

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    this.preparePush = async () => {
                        const result = await mintUniV3Position_USDC_WETH({
                            fee: 3000,
                            tickLower: -887220,
                            tickUpper: 887220,
                            usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                            wethAmount: BigNumber.from(10).pow(18),
                        });
                        await this.positionManager.functions[
                            "safeTransferFrom(address,address,uint256)"
                        ](
                            this.deployer.address,
                            this.uniV3Vault.address,
                            result.tokenId
                        );
                    };

                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let uniV3VaultNft = startNft;
                    let erc20VaultNft = startNft + 1;

                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                uniV3PoolFee,
                            ],
                        }
                    );
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20VaultNft + 1,
                        [erc20VaultNft, uniV3VaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );
                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );
                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3VaultNft
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

                    this.uniV3Vault = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    );

                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );

                    for (let address of [
                        this.deployer.address,
                        this.uniV3Vault.address,
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

        describe("#depositorsAllowlist", () => {
            it("returns non zero length of depositorsAllowlist", async () => {
                expect(
                    (await this.subject.depositorsAllowlist()).length
                ).to.not.be.equal(0);
            });
        });

        describe("#addDepositorsToAllowlist", () => {
            it("adds depositor to allow list", async () => {
                let newDepositor = randomAddress();
                expect(await this.subject.depositorsAllowlist()).to.not.contain(
                    newDepositor
                );
                await this.subject
                    .connect(this.admin)
                    .addDepositorsToAllowlist([newDepositor]);
                expect(await this.subject.depositorsAllowlist()).to.contain(
                    newDepositor
                );
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .addDepositorsToAllowlist([randomAddress()])
                    ).to.not.be.reverted;
                });
                it("not allowed: deployer", async () => {
                    await expect(
                        this.subject.addDepositorsToAllowlist([randomAddress()])
                    ).to.be.reverted;
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .addDepositorsToAllowlist([randomAddress()])
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#removeDepositorsFromAllowlist", () => {
            it("removes depositor to allow list", async () => {
                let newDepositor = randomAddress();
                expect(await this.subject.depositorsAllowlist()).to.not.contain(
                    newDepositor
                );
                await this.subject
                    .connect(this.admin)
                    .addDepositorsToAllowlist([newDepositor]);
                expect(await this.subject.depositorsAllowlist()).to.contain(
                    newDepositor
                );
                await this.subject
                    .connect(this.admin)
                    .removeDepositorsFromAllowlist([newDepositor]);
                expect(await this.subject.depositorsAllowlist()).to.not.contain(
                    newDepositor
                );
            });

            describe("access control:", () => {
                it("allowed: admin", async () => {
                    await expect(
                        this.subject
                            .connect(this.admin)
                            .removeDepositorsFromAllowlist([randomAddress()])
                    ).to.not.be.reverted;
                });
                it("not allowed: deployer", async () => {
                    await expect(
                        this.subject.removeDepositorsFromAllowlist([
                            randomAddress(),
                        ])
                    ).to.be.reverted;
                });
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .removeDepositorsFromAllowlist([
                                    randomAddress(),
                                ])
                        ).to.be.reverted;
                    });
                });
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${ERC20_ROOT_VAULT_INTERFACE_ID} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        ERC20_ROOT_VAULT_INTERFACE_ID
                    )
                ).to.be.true;
            });

            describe("edge cases:", () => {
                describe("when contract does not support the given interface", () => {
                    it("returns false", async () => {
                        expect(
                            await this.subject.supportsInterface(
                                YEARN_VAULT_INTERFACE_ID
                            )
                        ).to.be.false;
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .supportsInterface(
                                    ERC20_ROOT_VAULT_INTERFACE_ID
                                )
                        ).to.not.be.reverted;
                    });
                });
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

            // it("initializes contract successfully", async () => {
            //     await withSigner(
            //         this.erc20VaultGovernance.address,
            //         async (signer) => {
            //             await expect(
            //                 this.subject
            //                     .connect(signer)
            //                     .initialize(this.nft, [
            //                         this.usdc.address,
            //                         this.weth.address,
            //                     ],
            //                     randomAddress(),
            //                     [
            //                         this.usdc.address,
            //                         this.weth.address,
            //                     ],
            //                     )
            //             ).to.not.be.reverted;
            //         }
            //     );
            // });

            describe("edge cases:", () => {
                describe("when subvaultNFTs length is 0", () => {
                    it(`reverts with ${Exceptions.EMPTY_LIST}`, async () => {
                        await withSigner(
                            this.erc20VaultGovernance.address, // what to write here????
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(
                                            this.nft,
                                            [
                                                this.usdc.address,
                                                this.weth.address,
                                            ],
                                            randomAddress(),
                                            []
                                        )
                                ).to.be.revertedWith(Exceptions.EMPTY_LIST);
                            }
                        );
                    });
                });

                describe("when one of subvaultNFT is 0", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        await withSigner(
                            this.erc20VaultGovernance.address, // what to write here????
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .initialize(
                                            this.nft,
                                            [
                                                this.usdc.address,
                                                this.weth.address,
                                            ],
                                            randomAddress(),
                                            [0, randomInt(100)]
                                        )
                                ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                            }
                        );
                    });
                });

                // describe("when vault's nft is not 0", () => {
                //     it(`reverts with ${Exceptions.INIT}`, async () => {
                //         await ethers.provider.send("hardhat_setStorageAt", [
                //             this.subject.address,
                //             "0x4", // address of _nft
                //             "0x0000000000000000000000000000000000000000000000000000000000000007",
                //         ]);
                //         await expect(
                //             this.subject.initialize(this.nft, [
                //                 this.usdc.address,
                //                 this.weth.address,
                //             ])
                //         ).to.be.revertedWith(Exceptions.INIT);
                //     });
                // });
                // describe("when tokens are not sorted", () => {
                //     it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                //         await expect(
                //             this.subject.initialize(this.nft, [
                //                 this.weth.address,
                //                 this.usdc.address,
                //             ])
                //         ).to.be.revertedWith(Exceptions.INVARIANT);
                //     });
                // });
                // describe("when tokens are not unique", () => {
                //     it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                //         await expect(
                //             this.subject.initialize(this.nft, [
                //                 this.weth.address,
                //                 this.weth.address,
                //             ])
                //         ).to.be.revertedWith(Exceptions.INVARIANT);
                //     });
                // });
                // describe("when setting zero nft", () => {
                //     it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                //         await expect(
                //             this.subject.initialize(0, [
                //                 this.usdc.address,
                //                 this.weth.address,
                //             ])
                //         ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                //     });
                // });
                // describe("when token has no permission to become a vault token", () => {
                //     it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                //         await this.protocolGovernance
                //             .connect(this.admin)
                //             .revokePermissions(this.usdc.address, [
                //                 PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                //             ]);
                //         await withSigner(
                //             this.erc20VaultGovernance.address,
                //             async (signer) => {
                //                 await expect(
                //                     this.subject
                //                         .connect(signer)
                //                         .initialize(this.nft, [
                //                             this.usdc.address,
                //                             this.weth.address,
                //                         ])
                //                 ).to.be.revertedWith(Exceptions.FORBIDDEN);
                //             }
                //         );
                //     });
                // });
            });
        });

        describe("#deposit", () => {
            // it("emits Deposit event", async () => {
            //     expect(
            //         await this.subject.deposit(, BigNumber.from(randomInt(100))
            //         )
            //     ).to.emit(this.subject, "Deposit");
            // });

            describe("edge cases:", () => {
                describe("when deposit is disabled", () => {
                    it(`reverted with ${Exceptions.FORBIDDEN}`, async () => {
                        await expect(
                            this.subject.deposit(
                                [],
                                BigNumber.from(randomInt(100))
                            )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });

            // describe("access control:", () => {
            //     it("allowed: any address", async () => {
            //         await withSigner(randomAddress(), async (signer) => {
            //             await expect(
            //                 this.subject
            //                     .connect(signer)
            //                     .deposit(
            //                         [], BigNumber.from(randomInt(100))
            //                     )
            //             ).to.not.be.reverted;
            //         });
            //     });
            // });
        });
    }
);
