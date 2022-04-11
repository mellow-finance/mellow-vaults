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

type CustomContext = {};

type DeployOptions = {};

contract<UniV2Validator, DeployOptions, CustomContext>(
    "UniV2Validator",
    function () {
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

                    this.EXACT_INPUT_SELECTOR =
                        await this.subject.EXACT_INPUT_SELECTOR();
                    this.EXACT_OUTPUT_SELECTOR =
                        await this.subject.EXACT_OUTPUT_SELECTOR();
                    this.EXACT_ETH_INPUT_SELECTOR =
                        await this.subject.EXACT_ETH_INPUT_SELECTOR();
                    this.EXACT_ETH_OUTPUT_SELECTOR =
                        await this.subject.EXACT_ETH_OUTPUT_SELECTOR();
                    this.EXACT_TOKENS_INPUT_SELECTOR =
                        await this.subject.EXACT_TOKENS_INPUT_SELECTOR();
                    this.EXACT_TOKENS_OUTPUT_SELECTOR =
                        await this.subject.EXACT_TOKENS_OUTPUT_SELECTOR();

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

            it("reverts if wrong selector", async () => {
                await withSigner(randomAddress(), async (signer) => {
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
                    ).to.be.revertedWith(Exceptions.INVALID_SELECTOR);
                });
            });

            it("reverts if path too small", async () => {
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
                                    this.EXACT_ETH_INPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "uint256",
                                            "address[]",
                                            "address",
                                            "uint256",
                                        ],
                                        [
                                            generateSingleParams(uint256),
                                            [randomAddress()],
                                            randomAddress(),
                                            generateSingleParams(uint256),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                    }
                );
            });

            it("reverts if not a vault token", async () => {
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
                                    this.EXACT_ETH_INPUT_SELECTOR,
                                    encodeToBytes(
                                        [
                                            "uint256",
                                            "address[]",
                                            "address",
                                            "uint256",
                                        ],
                                        [
                                            generateSingleParams(uint256),
                                            [randomAddress(), randomAddress()],
                                            randomAddress(),
                                            generateSingleParams(uint256),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    }
                );
            });

            it("reverts if tokens are the same", async () => {
                await withSigner(await this.vault.address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                this.swapRouterAddress,
                                generateSingleParams(uint256),
                                this.EXACT_ETH_INPUT_SELECTOR,
                                encodeToBytes(
                                    [
                                        "uint256",
                                        "address[]",
                                        "address",
                                        "uint256",
                                    ],
                                    [
                                        generateSingleParams(uint256),
                                        [this.usdc.address, this.usdc.address],
                                        randomAddress(),
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                });
            });

            it("reverts if pool has no approve permission", async () => {
                await withSigner(await this.vault.address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                this.swapRouterAddress,
                                generateSingleParams(uint256),
                                this.EXACT_ETH_INPUT_SELECTOR,
                                encodeToBytes(
                                    [
                                        "uint256",
                                        "address[]",
                                        "address",
                                        "uint256",
                                    ],
                                    [
                                        generateSingleParams(uint256),
                                        [this.dai.address, this.usdc.address],
                                        randomAddress(),
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });

            it("reverts if sender is not a reciever", async () => {
                await withSigner(await this.vault.address, async (signer) => {
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
                                this.EXACT_ETH_INPUT_SELECTOR,
                                encodeToBytes(
                                    [
                                        "uint256",
                                        "address[]",
                                        "address",
                                        "uint256",
                                    ],
                                    [
                                        generateSingleParams(uint256),
                                        [this.dai.address, this.usdc.address],
                                        randomAddress(),
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.be.reverted;
                });
            });

            it("pass", async () => {
                await withSigner(await this.vault.address, async (signer) => {
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
                                this.EXACT_ETH_INPUT_SELECTOR,
                                encodeToBytes(
                                    [
                                        "uint256",
                                        "address[]",
                                        "address",
                                        "uint256",
                                    ],
                                    [
                                        generateSingleParams(uint256),
                                        [this.dai.address, this.usdc.address],
                                        signer.address,
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.not.be.reverted;
                });
            });

            it("reverts if value is not zero", async () => {
                await withSigner(
                    await this.erc20VaultSingleton.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .validate(
                                    randomAddress(),
                                    this.swapRouterAddress,
                                    generateSingleParams(uint256).add(1),
                                    this.EXACT_ETH_OUTPUT_SELECTOR,
                                    randomBytes(32)
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                    }
                );
            });

            it("reverts if sender is not reciever", async () => {
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
                                    this.EXACT_ETH_OUTPUT_SELECTOR,
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
                        ).to.be.reverted;
                    }
                );
            });

            it("reverts if path too small", async () => {
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
                                    this.EXACT_ETH_OUTPUT_SELECTOR,
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
                                            [randomAddress()],
                                            signer.address,
                                            generateSingleParams(uint256),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                    }
                );
            });

            it("reverts if not a vault token", async () => {
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
                                    this.EXACT_ETH_OUTPUT_SELECTOR,
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
                                            [randomAddress(), randomAddress()],
                                            signer.address,
                                            generateSingleParams(uint256),
                                        ]
                                    )
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    }
                );
            });

            it("reverts if tokens are the same", async () => {
                await withSigner(await this.vault.address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                this.swapRouterAddress,
                                0,
                                this.EXACT_ETH_OUTPUT_SELECTOR,
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
                                        [this.usdc.address, this.usdc.address],
                                        signer.address,
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                });
            });

            it("reverts if pool has no approve permission", async () => {
                await withSigner(await this.vault.address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                this.swapRouterAddress,
                                0,
                                this.EXACT_ETH_OUTPUT_SELECTOR,
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
                                        [this.dai.address, this.usdc.address],
                                        signer.address,
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.be.revertedWith(Exceptions.FORBIDDEN);
                });
            });

            it("pass", async () => {
                this.protocolGovernance
                    .connect(this.admin)
                    .stagePermissionGrants(this.pool, [
                        PermissionIdsLibrary.ERC20_APPROVE,
                    ]);
                await sleep(await this.protocolGovernance.governanceDelay());
                this.protocolGovernance
                    .connect(this.admin)
                    .commitAllPermissionGrantsSurpassedDelay();
                await withSigner(await this.vault.address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                randomAddress(),
                                this.swapRouterAddress,
                                0,
                                this.EXACT_ETH_OUTPUT_SELECTOR,
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
                                        [this.dai.address, this.usdc.address],
                                        signer.address,
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.not.be.reverted;
                });
            });
        });

        ValidatorBehaviour.call(this, {});
    }
);
