import hre, { network } from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    mintUSDCForVoltz,
    randomAddress,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, IMarginEngine, IPeriphery, IVAMM, VoltzVault } from "./types";
import {
    combineVaults,
    setupVault,
} from "../deploy/0000_utils";
import { VOLTZ_VAULT_INTERFACE_ID } from "./library/Constants";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    marginEngine: string;
    preparePush: () => any;
};

type DeployOptions = {};


contract<VoltzVault, DeployOptions, CustomContext>("VoltzVault", function () {
    this.timeout(200000);
    const initialTickLow = -6000;
    const initialTickHigh = 0;

    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { marginEngine, voltzPeriphery } =
                    await getNamedAccounts();

                this.periphery = voltzPeriphery;
                this.peripheryContract = await ethers.getContractAt("IPeriphery", this.periphery) as IPeriphery;

                this.marginEngine = marginEngine;
                this.marginEngineContract = await ethers.getContractAt("IMarginEngine", this.marginEngine) as IMarginEngine;
                this.vammContract = await ethers.getContractAt("IVAMM", await this.marginEngineContract.vamm()) as IVAMM;

                this.preparePush = async () => {
                    
                    await withSigner("0xb527e950fc7c4f581160768f48b3bfa66a7de1f0", async (s) => {
                        await expect(
                            this.marginEngineContract
                                .connect(s)
                                .setIsAlpha(false)
                        ).to.not.be.reverted;

                        await expect(
                            this.vammContract
                                .connect(s)
                                .setIsAlpha(false)
                        ).to.not.be.reverted;
                    });

                    await mintUSDCForVoltz({
                        tickLower: initialTickLow,
                        tickUpper: initialTickHigh,
                        usdcAmount: BigNumber.from(10).pow(6).mul(10000),
                    });
                };

                const tokens = [this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let voltzVaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                await setupVault(hre, voltzVaultNft, "VoltzVaultGovernance", {
                    createVaultArgs: [
                        tokens,
                        this.deployer.address,
                        marginEngine,
                        initialTickLow,
                        initialTickHigh
                    ],
                });

                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, voltzVaultNft],
                    this.deployer.address,
                    this.deployer.address
                );

                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );

                const voltzVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    voltzVaultNft
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
                    "VoltzVault",
                    voltzVault
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
                        BigNumber.from(10).pow(6).mul(3000)
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

    describe("sequences of operations", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
                await this.usdc
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
            });
        });

        it("returns total value locked", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(3000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [
                    BigNumber.from(10).pow(6).mul(3000),
                ],
                encodeToBytes(
                    ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                    [
                        BigNumber.from(0),
                        BigNumber.from(0),
                        BigNumber.from(0),
                        false,
                        0,
                        0,
                        false,
                        0
                    ]
                )
            );
            const result = await this.subject.tvl();
            for (let amountsId = 0; amountsId < 2; ++amountsId) {
                expect(result[amountsId][0]).to.be.equal(BigNumber.from(10).pow(6).mul(3000));
            }
        });

        describe("edge cases:", () => {
            describe("when there are no initial funds", () => {
                it("returns zeroes", async () => {
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0]).eq(0);
                    }
                });
            });
        });

        describe("perfors operations along push", () => {
            describe("mint in push", () => {
                it("mint with no leverage in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(10).pow(6).mul(3000),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0]).to.be.equal(BigNumber.from(10).pow(6).mul(3000));
                    }
                });
    
                it("mint with leverage (10x) in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(10).pow(6).mul(3000).mul(10),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0]).to.be.equal(BigNumber.from(10).pow(6).mul(3000));
                    }
                });
    
                it("mint with too much leverage (10000x) in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await expect(this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(10).pow(6).mul(3000).mul(10000),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    )).to.be.reverted;
                });
            });

            describe("trade fixed in push", () => {
                it("trade fixed with no leverage in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(0),
                                BigNumber.from(10).pow(6).mul(3000),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0].lt(BigNumber.from(10).pow(6).mul(3000)));
                        expect(result[amountsId][0].gt(0));
                    }
                });
    
                it("trade fixed with leverage (10x) in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(0),
                                BigNumber.from(10).pow(6).mul(3000).mul(10),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0].lt(BigNumber.from(10).pow(6).mul(3000)));
                        expect(result[amountsId][0].gt(0));
                    }
                });

                it("trade fixed with too much leverage (10000x) in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await expect(this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(0),
                                BigNumber.from(10).pow(6).mul(3000).mul(10000),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    )).to.be.reverted;
                });
            });

            describe("trade variable in push", () => {
                it("trade variable with no leverage in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(0),
                                BigNumber.from(10).pow(6).mul(3000).mul(-1),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0].lt(BigNumber.from(10).pow(6).mul(3000)));
                        expect(result[amountsId][0].gt(0));
                    }
                });
    
                it("trade variable with leverage (10x) in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(0),
                                BigNumber.from(10).pow(6).mul(3000).mul(10).mul(-1),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0].lt(BigNumber.from(10).pow(6).mul(3000)));
                        expect(result[amountsId][0].gt(0));
                    }
                });

                it("trade variable with too much leverage (10000x) in push", async () => {
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
        
                    await this.preparePush();
                    await expect(this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(0),
                                BigNumber.from(10).pow(6).mul(3000).mul(10000).mul(-1),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    )).to.be.reverted;
                });
            });
        });

        describe("rebalances position", () => {
            const rebalanceTickLow = -7200;
            const rebalanceTickHigh = 0;

            it("direct rebalance fails if liquidity in the current position", async () => {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(3000)
                );
    
                await this.preparePush();
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                           BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );
                
                await expect(this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(0),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            true,
                            rebalanceTickLow,
                            rebalanceTickHigh,
                            false,
                            0
                        ]
                    )
                )).to.be.reverted;
            }); 

            it("rebalance", async () => {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(3000)
                );
    
                await this.preparePush();
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                const erc20VaultBalanceS = await this.usdc.balanceOf(this.erc20Vault.address);

                await this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(2000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000).mul(-1),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                const erc20VaultBalanceE = await this.usdc.balanceOf(this.erc20Vault.address);
                expect(erc20VaultBalanceE.sub(erc20VaultBalanceS)).to.be.equal(BigNumber.from(10).pow(6).mul(2000));

                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(2000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            true,
                            rebalanceTickLow,
                            rebalanceTickHigh,
                            false,
                            0
                        ]
                    )
                );

                const result = await this.subject.tvl();
                for (let amountsId = 0; amountsId < 2; ++amountsId) {
                    expect(result[amountsId][0]).to.be.equal(BigNumber.from(10).pow(6).mul(3000));
                }
            }); 

            it("settle all opened positions at once", async () => {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(3000)
                );
    
                await this.preparePush();

                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                await this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(2000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000).mul(-1),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(2000)
                );
                
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(2000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            true,
                            rebalanceTickLow,
                            rebalanceTickHigh,
                            false,
                            0
                        ]
                    )
                );

                // advance time by 60 days to reach maturity
                await network.provider.send("evm_increaseTime", [60 * 60 * 24 * 60]);
                await network.provider.send("evm_mine", []);

                {
                    const numberOfClosedPositions = await this.subject.closing();
                    expect(numberOfClosedPositions).to.be.equal(BigNumber.from(0));
                }
                
                const openedPositions = await this.subject.numberOpenedPositions();
                await this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            true,
                            openedPositions
                        ]
                    )
                );

                {
                    const numberOfClosedPositions = await this.subject.closing();
                    expect(numberOfClosedPositions).to.be.equal(BigNumber.from(2));
                }
            }); 

            it("multiple rebalance", async () => {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(6000)
                );
    
                await this.preparePush();
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(6000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                const number_of_rebalances = 5;
                for (let i = 0; i < number_of_rebalances; i++) {
                    await this.subject.pull(
                        this.erc20Vault.address,
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(1000).mul((number_of_rebalances - i)),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(10).pow(6).mul(3000).mul(-1),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
    
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(1000).mul((number_of_rebalances - i))
                    );
                    
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(1000).mul((number_of_rebalances - i)),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(10).pow(6).mul(3000),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                true,
                                -120 * (i+1),
                                120 * (i+1),
                                false,
                                0
                            ]
                        )
                    );
                };

                const result = await this.subject.tvl();
                for (let amountsId = 0; amountsId < 2; ++amountsId) {
                    expect(result[amountsId][0]).to.be.equal(BigNumber.from(10).pow(6).mul(6000));
                }
            }); 

            it("settle all positions in batches", async () => {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(6000)
                );
    
                await this.preparePush();
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(6000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                const number_of_rebalances = 5;
                for (let i = 0; i < number_of_rebalances; i++) {
                    await this.subject.pull(
                        this.erc20Vault.address,
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(1000).mul((number_of_rebalances - i)),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(10).pow(6).mul(3000).mul(-1),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );
    
                    await mint(
                        "USDC",
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(1000).mul((number_of_rebalances - i))
                    );
                    
                    await this.subject.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(1000).mul((number_of_rebalances - i)),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(10).pow(6).mul(3000),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                true,
                                -120 * (i+1),
                                120 * (i+1),
                                false,
                                0
                            ]
                        )
                    );
                };

                // advance time by 60 days to reach maturity
                await network.provider.send("evm_increaseTime", [60 * 60 * 24 * 60]);
                await network.provider.send("evm_mine", []);

                {
                    const numberOfClosedPositions = await this.subject.closing();
                    expect(numberOfClosedPositions).to.be.equal(BigNumber.from(0));
                }
                
                await this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            true,
                            2
                        ]
                    )
                );

                {
                    const numberOfClosedPositions = await this.subject.closing();
                    expect(numberOfClosedPositions).to.be.equal(BigNumber.from(2));
                }
                
                await this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            true,
                            2
                        ]
                    )
                );

                {
                    const numberOfClosedPositions = await this.subject.closing();
                    expect(numberOfClosedPositions).to.be.equal(BigNumber.from(4));
                }
                
                await this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            true,
                            2
                        ]
                    )
                );

                {
                    const numberOfClosedPositions = await this.subject.closing();
                    expect(numberOfClosedPositions).to.be.equal(BigNumber.from(6));
                }
            }); 

            it("tvl if fees accumulated", async () => {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(3000)
                );
    
                await this.preparePush();
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                await withSigner(randomAddress(), async (s) => {
                    await mint(
                        "USDC",
                        s.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );

                    await this.usdc.connect(s).approve(
                        this.periphery, 
                        BigNumber.from(10).pow(6).mul(1000)
                    );

                    const swapParams = {
                        marginEngine: this.marginEngine,
                        isFT: true,
                        notional: BigNumber.from(10).pow(6).mul(1000),
                        sqrtPriceLimitX96: BigNumber.from("2507794810551837817144115957739"),
                        tickLower: -60,
                        tickUpper: 0,
                        marginDelta: BigNumber.from(10).pow(6).mul(1000),
                    };
                    await this.peripheryContract.connect(s).swap(swapParams);
                });

                {
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0].eq(BigNumber.from(10).pow(6).mul(3000)));
                    }
                }
                
                {
                    await this.subject.updateTvl();
                    const result = await this.subject.tvl();
                    for (let amountsId = 0; amountsId < 2; ++amountsId) {
                        expect(result[amountsId][0].gt(BigNumber.from(10).pow(6).mul(3000)));
                    }
                }
                
            }); 

            it("maximum withdrawal to still cover position", async () => {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(3000)
                );
    
                await this.preparePush();
                await this.subject.push(
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(10).pow(6).mul(3000).mul(10),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                const amounts = await this.subject.callStatic.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );
                
                await this.subject.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                    ],
                    encodeToBytes(
                        ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                            false,
                            0,
                            0,
                            false,
                            0
                        ]
                    )
                );

                expect(amounts[0].lt(BigNumber.from(10).pow(6).mul(3000)));
            });
        });
    });

    describe("#supportsInterface", () => {
        it(`returns true if this contract supports ${VOLTZ_VAULT_INTERFACE_ID} interface`, async () => {
            expect(
                await this.subject.supportsInterface(VOLTZ_VAULT_INTERFACE_ID)
            ).to.be.true;
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (s) => {
                    await expect(
                        this.subject
                            .connect(s)
                            .supportsInterface(VOLTZ_VAULT_INTERFACE_ID)
                    ).to.not.be.reverted;
                });
            });
        });
    });
});
