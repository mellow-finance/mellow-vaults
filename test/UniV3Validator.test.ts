import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    encodeToBytes,
    generateSingleParams,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { UniV3Validator } from "./types";
import { PermissionIdsLibrary } from "../deploy/0000_utils";
import { ValidatorBehaviour } from "./behaviors/validator";
import Exceptions from "./library/Exceptions";
import { randomBytes } from "crypto";
import { uint256, uint8 } from "./library/property";

type CustomContext = {};

type DeployOptions = {};

contract<UniV3Validator, DeployOptions, CustomContext>(
    "UniV3Validator",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get("UniV3Validator");
                    this.subject = await ethers.getContractAt(
                        "UniV3Validator",
                        address
                    );
                    this.swapRouterAddress = await this.subject.swapRouter();

                    this.EXACT_INPUT_SINGLE_SELECTOR =
                        await this.subject.EXACT_INPUT_SINGLE_SELECTOR();
                    this.EXACT_INPUT_SELECTOR =
                        await this.subject.EXACT_INPUT_SELECTOR();
                    this.EXACT_OUTPUT_SINGLE_SELECTOR =
                        await this.subject.EXACT_OUTPUT_SINGLE_SELECTOR();
                    this.EXACT_OUTPUT_SELECTOR =
                        await this.subject.EXACT_OUTPUT_SELECTOR();

                    const vaultTokens = [this.dai.address, this.usdc.address];
                    let vaultOwner = randomAddress();
                    const { vault } = await this.erc20VaultGovernance
                        .connect(this.admin)
                        .callStatic.createVault(vaultTokens, vaultOwner);
                    await this.erc20VaultGovernance
                        .connect(this.admin)
                        .createVault(vaultTokens, vaultOwner);
                    this.vault = await ethers.getContractAt(
                        "ERC20Vault",
                        vault
                    );
                    this.uniswapV3Factory = await ethers.getContractAt(
                        "IUniswapV3Factory",
                        await this.subject.factory()
                    );
                    this.fee = 3000;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#validate", () => {
            it("reverts if addr is not swap", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                randomAddress(),
                                generateSingleParams(uint256),
                                randomBytes(4),
                                randomBytes(32)
                            )
                    ).to.be.revertedWith(Exceptions.INVALID_TARGET);
                });
            });

            it("reverts if value is not zero", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                this.swapRouterAddress,
                                generateSingleParams(uint256).add(1),
                                randomBytes(4),
                                randomBytes(32)
                            )
                    ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                });
            });

            it("reverts if selector is wrong", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                this.swapRouterAddress,
                                0,
                                randomBytes(4),
                                randomBytes(32)
                            )
                    ).to.be.revertedWith(Exceptions.INVALID_SELECTOR);
                });
            });

            describe("EXACT_INPUT_SINGLE_SELECTOR", async () => {
                it("reverts if recipient is not sender", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            randomAddress(),
                                            randomAddress(),
                                            generateSingleParams(uint8),
                                            randomAddress(),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TARGET);
                    });
                });

                it("reverts if not a vault token", async () => {
                    await withSigner(
                        this.erc20RootVaultSingleton.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        randomAddress(),
                                        this.swapRouterAddress,
                                        0,
                                        this.EXACT_INPUT_SINGLE_SELECTOR,
                                        encodeToBytes(
                                            [
                                                "address",
                                                "address",
                                                "uint24",
                                                "address",
                                                "uint256",
                                                "uint256",
                                                "uint256",
                                                "uint160",
                                            ],
                                            [
                                                randomAddress(),
                                                randomAddress(),
                                                generateSingleParams(uint8),
                                                signer.address,
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint8),
                                            ]
                                        )
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                        }
                    );
                });

                it("reverts if tokens are the same", async () => {
                    await withSigner(this.vault.address, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            this.usdc.address,
                                            this.usdc.address,
                                            generateSingleParams(uint8),
                                            signer.address,
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });

                it("reverts if pool has no permisson", async () => {
                    await withSigner(this.vault.address, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            this.dai.address,
                                            this.usdc.address,
                                            generateSingleParams(uint8),
                                            signer.address,
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                it("pass", async () => {
                    let pool = await this.uniswapV3Factory
                        .connect(this.admin)
                        .callStatic.getPool(
                            this.dai.address,
                            this.usdc.address,
                            this.fee
                        );
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(pool, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    await withSigner(this.vault.address, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            this.dai.address,
                                            this.usdc.address,
                                            this.fee,
                                            signer.address,
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("EXACT_OUTPUT_SINGLE_SELECTOR", async () => {
                it("reverts if recipient is not sender", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            randomAddress(),
                                            randomAddress(),
                                            generateSingleParams(uint8),
                                            randomAddress(),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TARGET);
                    });
                });

                it("reverts if not a vault token", async () => {
                    await withSigner(
                        this.erc20RootVaultSingleton.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        randomAddress(),
                                        this.swapRouterAddress,
                                        0,
                                        this.EXACT_OUTPUT_SINGLE_SELECTOR,
                                        encodeToBytes(
                                            [
                                                "address",
                                                "address",
                                                "uint24",
                                                "address",
                                                "uint256",
                                                "uint256",
                                                "uint256",
                                                "uint160",
                                            ],
                                            [
                                                randomAddress(),
                                                randomAddress(),
                                                generateSingleParams(uint8),
                                                signer.address,
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint8),
                                            ]
                                        )
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                        }
                    );
                });

                it("reverts if tokens are the same", async () => {
                    await withSigner(this.vault.address, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            this.usdc.address,
                                            this.usdc.address,
                                            generateSingleParams(uint8),
                                            signer.address,
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });

                it("reverts if pool has no permisson", async () => {
                    await withSigner(this.vault.address, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            this.dai.address,
                                            this.usdc.address,
                                            generateSingleParams(uint8),
                                            signer.address,
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                it("pass", async () => {
                    let pool = await this.uniswapV3Factory
                        .connect(this.admin)
                        .callStatic.getPool(
                            this.dai.address,
                            this.usdc.address,
                            this.fee
                        );
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(pool, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    await withSigner(this.vault.address, async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SINGLE_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "address",
                                            "address",
                                            "uint24",
                                            "address",
                                            "uint256",
                                            "uint256",
                                            "uint256",
                                            "uint160",
                                        ],
                                        [
                                            this.dai.address,
                                            this.usdc.address,
                                            this.fee,
                                            signer.address,
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint256),
                                            generateSingleParams(uint8),
                                        ]
                                    )
                                )
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("EXACT_INPUT_SELECTOR", async () => {
                it("reverts if recipient is not sender", async () => {
                    let inputParams = {
                        path: randomBytes(40),
                        recipient: randomAddress(),
                        deadline: generateSingleParams(uint256),
                        amountIn: generateSingleParams(uint256),
                        amountOutMinimum: generateSingleParams(uint256),
                    };
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TARGET);
                    });
                });

                it("reverts if tokens are the same", async () => {
                    let token = randomBytes(20);
                    await withSigner(randomAddress(), async (signer) => {
                        let inputParams = {
                            path: Buffer.concat([token, randomBytes(3), token]),
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });

                it("reverts if no permission", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        let inputParams = {
                            path: randomBytes(43),
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                it("reverts if not a vault token", async () => {
                    let pool = await this.uniswapV3Factory
                        .connect(this.admin)
                        .callStatic.getPool(
                            this.dai.address,
                            this.weth.address,
                            this.fee
                        );
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(pool, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    let path = Buffer.concat([
                        Buffer.from(this.dai.address.slice(2), "hex"),
                        Buffer.from("000bb8", "hex"),
                        Buffer.from(this.weth.address.slice(2), "hex"),
                    ]);
                    await withSigner(this.vault.address, async (signer) => {
                        let inputParams = {
                            path: path,
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });

                it("pass", async () => {
                    let pool = await this.uniswapV3Factory
                        .connect(this.admin)
                        .callStatic.getPool(
                            this.dai.address,
                            this.usdc.address,
                            this.fee
                        );
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(pool, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    let path = Buffer.concat([
                        Buffer.from(this.dai.address.slice(2), "hex"),
                        Buffer.from("000bb8", "hex"),
                        Buffer.from(this.usdc.address.slice(2), "hex"),
                    ]);
                    await withSigner(this.vault.address, async (signer) => {
                        let inputParams = {
                            path: path,
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_INPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.not.be.reverted;
                    });
                });
            });

            describe("EXACT_OUTPUT_SELECTOR", async () => {
                it("reverts if recipient is not sender", async () => {
                    let inputParams = {
                        path: randomBytes(40),
                        recipient: randomAddress(),
                        deadline: generateSingleParams(uint256),
                        amountIn: generateSingleParams(uint256),
                        amountOutMinimum: generateSingleParams(uint256),
                    };
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TARGET);
                    });
                });

                it("reverts if tokens are the same", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        let token = randomBytes(20);
                        let inputParams = {
                            path: Buffer.concat([token, randomBytes(3), token]),
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });

                it("reverts if no permission", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        let inputParams = {
                            path: randomBytes(43),
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                it("reverts if not a vault token", async () => {
                    let pool = await this.uniswapV3Factory
                        .connect(this.admin)
                        .callStatic.getPool(
                            this.dai.address,
                            this.weth.address,
                            this.fee
                        );
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(pool, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    let path = Buffer.concat([
                        Buffer.from(this.dai.address.slice(2), "hex"),
                        Buffer.from("000bb8", "hex"),
                        Buffer.from(this.weth.address.slice(2), "hex"),
                    ]);
                    await withSigner(this.vault.address, async (signer) => {
                        let inputParams = {
                            path: path,
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    });
                });

                it("pass", async () => {
                    let pool = await this.uniswapV3Factory
                        .connect(this.admin)
                        .callStatic.getPool(
                            this.dai.address,
                            this.usdc.address,
                            this.fee
                        );
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(pool, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    let path = Buffer.concat([
                        Buffer.from(this.dai.address.slice(2), "hex"),
                        Buffer.from("000bb8", "hex"),
                        Buffer.from(this.usdc.address.slice(2), "hex"),
                    ]);
                    await withSigner(this.vault.address, async (signer) => {
                        let inputParams = {
                            path: path,
                            recipient: signer.address,
                            deadline: generateSingleParams(uint256),
                            amountIn: generateSingleParams(uint256),
                            amountOutMinimum: generateSingleParams(uint256),
                        };
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    0,
                                    this.EXACT_OUTPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "tuple(" +
                                                "bytes path, " +
                                                "address recipient, " +
                                                "uint256 deadline, " +
                                                "uint256 amountIn, " +
                                                "uint256 amountOutMinimum)",
                                        ],
                                        [inputParams]
                                    )
                                )
                        ).to.not.be.reverted;
                    });
                });
            });
        });

        ValidatorBehaviour.call(this, {});
    }
);
