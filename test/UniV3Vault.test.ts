import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    mintUniV3Position_USDC_WETH,
    mintUniV3Position_WBTC_WETH,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, UniV3Vault } from "./types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import {
    INTEGRATION_VAULT_INTERFACE_ID,
    UNIV3_VAULT_INTERFACE_ID,
} from "./library/Constants";
import Exceptions from "./library/Exceptions";
import { Signer } from "ethers";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<UniV3Vault, DeployOptions, CustomContext>("UniV3Vault", function () {
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
                        this.subject.address,
                        result.tokenId
                    );
                };

                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let uniV3VaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                await setupVault(hre, uniV3VaultNft, "UniV3VaultGovernance", {
                    createVaultArgs: [
                        tokens,
                        this.deployer.address,
                        uniV3PoolFee,
                    ],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

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

                this.subject = await ethers.getContractAt(
                    "UniV3Vault",
                    uniV3Vault
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
                encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
                )
            );
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
            describe("when push was made but there was no minted position", () => {
                it("returns zeroes", async () => {
                    await this.subject.push(
                        [this.usdc.address, this.weth.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(10).pow(18).mul(1),
                        ],
                        []
                    );
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        for (let tokenId = 0; tokenId < 2; ++tokenId) {
                            expect(result[amountsId][tokenId]).equal(0);
                        }
                    }
                });
            });
        });
    });

    describe("#liquidityToTokenAmounts", () => {
        it("returns tokenAmounts corresponding to liquidity", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });
            await this.positionManager.functions[
                "safeTransferFrom(address,address,uint256)"
            ](this.deployer.address, this.subject.address, result.tokenId);
            let res = await this.subject.liquidityToTokenAmounts(
                result.liquidity
            );
            expect(res[0].gt(0) && res[1].gt(0));
        });
    });

    describe("#onERC721Received", () => {
        it("updates vault's uniV3Nft", async () => {
            const result = await mintUniV3Position_USDC_WETH({
                fee: 3000,
                tickLower: -887220,
                tickUpper: 887220,
                usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                wethAmount: BigNumber.from(10).pow(18),
            });
            await withSigner(this.positionManager.address, async (signer) => {
                await this.subject
                    .connect(signer)
                    .onERC721Received(
                        this.deployer.address,
                        this.deployer.address,
                        result.tokenId,
                        []
                    );
            });
            expect(await this.subject.uniV3Nft()).to.be.equal(result.tokenId);
        });

        describe("edge cases:", () => {
            describe("when msg.sender is not a position manager", () => {
                it("reverts", async () => {
                    await expect(
                        this.subject.onERC721Received(
                            this.deployer.address,
                            this.deployer.address,
                            0,
                            []
                        )
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });
            describe("when operator is not a strategy", () => {
                it("reverts", async () => {
                    await withSigner(
                        this.positionManager.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .onERC721Received(
                                        randomAddress(),
                                        this.deployer.address,
                                        0,
                                        []
                                    )
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        }
                    );
                });
            });
            describe("when UniV3 token is not valid", () => {
                it("reverts", async () => {
                    const result = await mintUniV3Position_WBTC_WETH({
                        fee: 3000,
                        tickLower: -887220,
                        tickUpper: 887220,
                        wethAmount: BigNumber.from(10).pow(6).mul(3000),
                        wbtcAmount: BigNumber.from(10).pow(6),
                    });
                    await withSigner(
                        this.positionManager.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .onERC721Received(
                                        this.deployer.address,
                                        this.deployer.address,
                                        result.tokenId,
                                        [],
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                        }
                    );
                });
            });
            describe("prevent from adding nft while liquidity is not empty", () => {
                it("reverts", async () => {
                    const result = await mintUniV3Position_USDC_WETH({
                        fee: 3000,
                        tickLower: -887220,
                        tickUpper: 887220,
                        usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                        wethAmount: BigNumber.from(10).pow(18),
                    });
                    await withSigner(this.positionManager.address, async (signer) => {
                        await this.subject
                            .connect(signer)
                            .onERC721Received(
                                this.deployer.address,
                                this.deployer.address,
                                result.tokenId,
                                []
                            );
                    });
                    expect(await this.subject.uniV3Nft()).to.be.equal(result.tokenId);
                    await withSigner(this.positionManager.address, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .onERC721Received(
                                    this.deployer.address,
                                    this.deployer.address,
                                    result.tokenId,
                                    []
                            )
                        ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                    });
                });
            });
        });

        describe("access control:", () => {
            it("position manager: allowed", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: 3000,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                await withSigner(
                    this.positionManager.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .onERC721Received(
                                    this.deployer.address,
                                    this.deployer.address,
                                    result.tokenId,
                                    []
                                )
                        ).to.not.be.reverted;
                    }
                );
            });
            it("any other address: not allowed", async () => {
                await expect(
                    this.subject.onERC721Received(
                        this.deployer.address,
                        this.deployer.address,
                        0,
                        []
                    )
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
        });
    });

    describe("#positionManager", () => {
        it("returns INonfungiblePositionManager", async () => {
            const { uniswapV3PositionManager } = await getNamedAccounts();
            expect(await this.subject.positionManager()).to.be.equal(
                uniswapV3PositionManager
            );
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(this.subject.connect(s).positionManager()).to
                        .not.be.reverted;
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

        it("emits Initialized event", async () => {
            await withSigner(
                this.uniV3VaultGovernance.address,
                async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .initialize(
                                this.nft,
                                [this.usdc.address, this.weth.address],
                                uniV3PoolFee
                            )
                    ).to.emit(this.subject, "Initialized");
                }
            );
        });
        it("initializes contract successfully", async () => {
            await withSigner(
                this.uniV3VaultGovernance.address,
                async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .initialize(
                                this.nft,
                                [this.usdc.address, this.weth.address],
                                uniV3PoolFee
                            )
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
                        this.subject.initialize(
                            this.nft,
                            [this.usdc.address, this.weth.address],
                            uniV3PoolFee
                        )
                    ).to.be.revertedWith(Exceptions.INIT);
                });
            });
            describe("when tokens are not sorted", () => {
                it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                    await expect(
                        this.subject.initialize(
                            this.nft,
                            [this.weth.address, this.usdc.address],
                            uniV3PoolFee
                        )
                    ).to.be.revertedWith(Exceptions.INVARIANT);
                });
            });
            describe("when tokens are not unique", () => {
                it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                    await expect(
                        this.subject.initialize(
                            this.nft,
                            [this.weth.address, this.weth.address],
                            uniV3PoolFee
                        )
                    ).to.be.revertedWith(Exceptions.INVARIANT);
                });
            });
            describe("when tokens length is not equal to 2", () => {
                it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                    await expect(
                        this.subject.initialize(
                            this.nft,
                            [
                                this.weth.address,
                                this.usdc.address,
                                this.weth.address,
                            ],
                            uniV3PoolFee
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                });
            });
            describe("when setting zero nft", () => {
                it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                    await expect(
                        this.subject.initialize(
                            0,
                            [this.usdc.address, this.weth.address],
                            uniV3PoolFee
                        )
                    ).to.be.revertedWith(Exceptions.VALUE_ZERO);
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
                        this.uniV3VaultGovernance.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .initialize(
                                        this.nft,
                                        [this.usdc.address, this.weth.address],
                                        uniV3PoolFee
                                    )
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        }
                    );
                });
            });
        });
    });

    describe("#supportsInterface", () => {
        it(`returns true if this contract supports ${UNIV3_VAULT_INTERFACE_ID} interface`, async () => {
            expect(
                await this.subject.supportsInterface(UNIV3_VAULT_INTERFACE_ID)
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

    describe("#collectEarnings", () => {
        it("emits CollectedEarnings event", async () => {
            await this.preparePush();
            await expect(this.subject.collectEarnings()).to.emit(
                this.subject,
                "CollectedEarnings"
            );
        });
        it("collecting fees", async () => {
            await this.preparePush();
            await this.subject.push(
                [this.usdc.address, this.weth.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                    BigNumber.from(10).pow(18).mul(1),
                ],
                []
            );

            const { uniswapV3Router } = await getNamedAccounts();
            let swapRouter = await ethers.getContractAt(
                ISwapRouter,
                uniswapV3Router
            );
            await this.usdc.approve(
                swapRouter.address,
                ethers.constants.MaxUint256
            );
            let params = {
                tokenIn: this.usdc.address,
                tokenOut: this.weth.address,
                fee: uniV3PoolFee,
                recipient: this.deployer.address,
                deadline: ethers.constants.MaxUint256,
                amountIn: BigNumber.from(10).pow(6).mul(5000),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
            };
            await swapRouter.exactInputSingle(params);

            let zeroVaultBalance = await this.usdc.balanceOf(
                this.erc20Vault.address
            );
            await this.subject.collectEarnings();
            expect(await this.usdc.balanceOf(this.erc20Vault.address)).to.be.gt(
                zeroVaultBalance
            );
        });

        describe("edge cases:", () => {
            describe("when there is no minted position", () => {
                it("reverts", async () => {
                    await expect(
                        this.subject.collectEarnings()
                    ).to.be.revertedWith(
                        "ERC721: operator query for nonexistent token"
                    );
                });
            });
        });

        describe("access control:", () => {
            it("allowed: all addresses", async () => {
                await this.preparePush();
                await expect(this.subject.collectEarnings()).to.not.be.reverted;
            });
        });
    });

    integrationVaultBehavior.call(this, {});
});
