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
import { UniV2Validator } from "./types";
import { PermissionIdsLibrary } from "../deploy/0000_utils";
import { ValidatorBehaviour } from "./behaviors/validator";
import Exceptions from "./library/Exceptions";
import { randomBytes } from "crypto";
import { uint256 } from "./library/property";
import { ContractMetaBehaviour } from "./behaviors/contractMeta";

type CustomContext = {};

type DeployOptions = {};

contract<UniV2Validator, DeployOptions, CustomContext>(
    "UniV2Validator",
    function () {
        const EXACT_INPUT_SELECTOR = "0x38ed1739";
        const EXACT_OUTPUT_SELECTOR = "0x8803dbee";
        const EXACT_ETH_INPUT_SELECTOR = "0x7ff36ab5";
        const EXACT_ETH_OUTPUT_SELECTOR = "0x4a25d94a";
        const EXACT_TOKENS_INPUT_SELECTOR = "0x18cbafe5";
        const EXACT_TOKENS_OUTPUT_SELECTOR = "0xfb3bdb41";

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get("UniV2Validator");
                    this.subject = await ethers.getContractAt(
                        "UniV2Validator",
                        address
                    );
                    this.swapRouterAddress = await this.subject.swapRouter();

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
                    this.uniswapV2Factory = await ethers.getContractAt(
                        "IUniswapV2Factory",
                        await this.subject.factory()
                    );
                    this.pool = this.uniswapV2Factory.getPair(
                        this.dai.address,
                        this.usdc.address
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#validate", () => {
            describe(`selector is ${EXACT_ETH_INPUT_SELECTOR} or ${EXACT_TOKENS_OUTPUT_SELECTOR}`, async () => {
                it("successful validate", async () => {
                    await withSigner(
                        await this.vault.address,
                        async (signer) => {
                            this.protocolGovernance
                                .connect(this.admin)
                                .stagePermissionGrants(this.pool, [
                                    PermissionIdsLibrary.ERC20_APPROVE,
                                ]);
                            await sleep(
                                await this.protocolGovernance.governanceDelay()
                            );
                            this.protocolGovernance
                                .connect(this.admin)
                                .commitAllPermissionGrantsSurpassedDelay();
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        randomAddress(),
                                        this.swapRouterAddress,
                                        generateSingleParams(uint256),
                                        EXACT_ETH_INPUT_SELECTOR,
                                        encodeToBytes(
                                            [
                                                "uint256",
                                                "address[]",
                                                "address",
                                                "uint256",
                                            ],
                                            [
                                                generateSingleParams(uint256),
                                                [
                                                    this.dai.address,
                                                    this.usdc.address,
                                                ],
                                                signer.address,
                                                generateSingleParams(uint256),
                                            ]
                                        )
                                    )
                            ).to.not.be.reverted;
                        }
                    );
                });

                describe("edge cases:", () => {
                    describe("when addr is not swap", () => {
                        it(`reverts with ${Exceptions.INVALID_TARGET}`, async () => {
                            await withSigner(
                                randomAddress(),
                                async (signer) => {
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
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_TARGET
                                    );
                                }
                            );
                        });
                    });

                    describe("when selector is wrong", () => {
                        it(`reverts with ${Exceptions.INVALID_SELECTOR}`, async () => {
                            await withSigner(
                                randomAddress(),
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                generateSingleParams(uint256),
                                                randomBytes(4),
                                                randomBytes(32)
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_SELECTOR
                                    );
                                }
                            );
                        });
                    });

                    describe("when path is too small", () => {
                        it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                            await withSigner(
                                await this.erc20VaultSingleton.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                generateSingleParams(uint256),
                                                EXACT_ETH_INPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [randomAddress()],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_LENGTH
                                    );
                                }
                            );
                        });
                    });

                    describe("when not a vault token", () => {
                        it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                            await withSigner(
                                await this.erc20VaultSingleton.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                generateSingleParams(uint256),
                                                EXACT_ETH_INPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            randomAddress(),
                                                            randomAddress(),
                                                        ],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_TOKEN
                                    );
                                }
                            );
                        });
                    });

                    describe("when tokens are the same", () => {
                        it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                            await withSigner(
                                await this.vault.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                generateSingleParams(uint256),
                                                EXACT_ETH_INPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            this.usdc.address,
                                                            this.usdc.address,
                                                        ],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_TOKEN
                                    );
                                }
                            );
                        });
                    });

                    describe("when pool has no approve permission", () => {
                        it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                            await withSigner(
                                await this.vault.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                generateSingleParams(uint256),
                                                EXACT_ETH_INPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            this.dai.address,
                                                            this.usdc.address,
                                                        ],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                                }
                            );
                        });
                    });

                    describe("when sender is not a reciever", () => {
                        it(`reverts`, async () => {
                            await withSigner(
                                await this.vault.address,
                                async (signer) => {
                                    this.protocolGovernance
                                        .connect(this.admin)
                                        .stagePermissionGrants(this.pool, [
                                            PermissionIdsLibrary.ERC20_APPROVE,
                                        ]);
                                    await sleep(
                                        await this.protocolGovernance.governanceDelay()
                                    );
                                    this.protocolGovernance
                                        .connect(this.admin)
                                        .commitAllPermissionGrantsSurpassedDelay();
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                generateSingleParams(uint256),
                                                EXACT_ETH_INPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            this.dai.address,
                                                            this.usdc.address,
                                                        ],
                                                        randomAddress(),
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.reverted;
                                }
                            );
                        });
                    });
                });
            });
            describe(`selector is one of: ${EXACT_ETH_OUTPUT_SELECTOR}, ${EXACT_TOKENS_INPUT_SELECTOR}, ${EXACT_INPUT_SELECTOR}, ${EXACT_OUTPUT_SELECTOR}`, async () => {
                it("successful validate", async () => {
                    this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(this.pool, [
                            PermissionIdsLibrary.ERC20_APPROVE,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    this.protocolGovernance
                        .connect(this.admin)
                        .commitAllPermissionGrantsSurpassedDelay();
                    await withSigner(
                        await this.vault.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        randomAddress(),
                                        this.swapRouterAddress,
                                        0,
                                        EXACT_ETH_OUTPUT_SELECTOR,
                                        encodeToBytes(
                                            [
                                                "uint256",
                                                "uint256",
                                                "address[]",
                                                "address",
                                                "uint256",
                                            ],
                                            [
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint256),
                                                [
                                                    this.dai.address,
                                                    this.usdc.address,
                                                ],
                                                signer.address,
                                                generateSingleParams(uint256),
                                            ]
                                        )
                                    )
                            ).to.not.be.reverted;
                        }
                    );
                });

                describe("edge cases:", async () => {
                    describe("when value is not zero", async () => {
                        it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                            await withSigner(
                                await this.erc20VaultSingleton.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                generateSingleParams(
                                                    uint256
                                                ).add(1),
                                                EXACT_ETH_OUTPUT_SELECTOR,
                                                randomBytes(32)
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_VALUE
                                    );
                                }
                            );
                        });
                    });

                    describe("when sender is not reciever", async () => {
                        it(`reverts`, async () => {
                            await withSigner(
                                await this.erc20VaultSingleton.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                0,
                                                EXACT_ETH_OUTPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            this.dai.address,
                                                            this.usdc.address,
                                                        ],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.reverted;
                                }
                            );
                        });
                    });

                    describe("when path too small", async () => {
                        it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                            await withSigner(
                                await this.erc20VaultSingleton.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                0,
                                                EXACT_ETH_OUTPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [randomAddress()],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_LENGTH
                                    );
                                }
                            );
                        });
                    });

                    describe("when not a vault token", async () => {
                        it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                            await withSigner(
                                await this.erc20VaultSingleton.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                0,
                                                EXACT_ETH_OUTPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            randomAddress(),
                                                            randomAddress(),
                                                        ],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_TOKEN
                                    );
                                }
                            );
                        });
                    });

                    describe("when tokens are the same", async () => {
                        it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                            await withSigner(
                                await this.vault.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                0,
                                                EXACT_ETH_OUTPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            this.usdc.address,
                                                            this.usdc.address,
                                                        ],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(
                                        Exceptions.INVALID_TOKEN
                                    );
                                }
                            );
                        });
                    });

                    describe("when pool has no approve permission", async () => {
                        it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                            await withSigner(
                                await this.vault.address,
                                async (signer) => {
                                    await expect(
                                        this.subject
                                            .connect(signer)
                                            .validate(
                                                randomAddress(),
                                                this.swapRouterAddress,
                                                0,
                                                EXACT_ETH_OUTPUT_SELECTOR,
                                                encodeToBytes(
                                                    [
                                                        "uint256",
                                                        "uint256",
                                                        "address[]",
                                                        "address",
                                                        "uint256",
                                                    ],
                                                    [
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                        [
                                                            this.dai.address,
                                                            this.usdc.address,
                                                        ],
                                                        signer.address,
                                                        generateSingleParams(
                                                            uint256
                                                        ),
                                                    ]
                                                )
                                            )
                                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                                }
                            );
                        });
                    });
                });
            });
        });

        ValidatorBehaviour.call(this, {});
        ContractMetaBehaviour.call(this, {
            contractName: "UniV2Validator",
            contractVersion: "1.0.0",
        });
    }
);
