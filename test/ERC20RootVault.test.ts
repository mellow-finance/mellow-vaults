import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    withSigner,
    randomAddress,
    sleep,
    addSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    ERC20Vault,
    IntegrationVault,
    MockLpCallback,
    UniV3Vault,
    IERC20RootVaultGovernance,
    ERC20Token,
} from "./types";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import Exceptions from "./library/Exceptions";
import {
    ERC20_ROOT_VAULT_INTERFACE_ID,
    YEARN_VAULT_INTERFACE_ID,
} from "./library/Constants";
import { randomInt } from "crypto";
import { DelayedStrategyParamsStruct } from "./types/IERC20RootVaultGovernance";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { DelayedProtocolParamsStruct } from "./types/IERC20RootVaultGovernance";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
    integrationVault: IntegrationVault;
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

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#depositorsAllowlist", () => {
            const TEST_SIGNER = randomAddress();
            beforeEach(async () => {
                await this.subject
                    .connect(this.admin)
                    .addDepositorsToAllowlist([TEST_SIGNER]);
            });
            it("returns non zero length of depositorsAllowlist", async () => {
                var signers = await this.subject.depositorsAllowlist();
                expect(signers).contains(TEST_SIGNER);
            });
            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        var signers = await this.subject
                            .connect(signer)
                            .depositorsAllowlist();
                        expect(signers).contains(TEST_SIGNER);
                    });
                });
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

            describe("edge cases:", () => {
                describe("when subvaultNfts length is 0", () => {
                    it(`reverts with ${Exceptions.EMPTY_LIST}`, async () => {
                        await withSigner(
                            this.erc20VaultGovernance.address,
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

                describe("when one of subVault indexes is 0", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        await withSigner(
                            this.erc20VaultGovernance.address,
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

                describe("when subVault index is 0 (rootVault has itself as subVaul)", () => {
                    it(`reverts with ${Exceptions.DUPLICATE}`, async () => {
                        const startNft =
                            (
                                await this.vaultRegistry.vaultsCount()
                            ).toNumber() - 1;
                        await withSigner(
                            this.erc20RootVaultGovernance.address,
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
                                            [startNft]
                                        )
                                ).to.be.revertedWith(Exceptions.DUPLICATE);
                            }
                        );
                    });
                });

                describe("when subVault index index is 0", () => {
                    it(`reverts with ${Exceptions.DUPLICATE}`, async () => {
                        const startNft =
                            (
                                await this.vaultRegistry.vaultsCount()
                            ).toNumber() - 2;
                        await ethers.provider.send("hardhat_setStorageAt", [
                            this.vaultRegistry.address,
                            "0x5", // address of nft index
                            "0x0000000000000000000000000000000000000000000000000000000000000000",
                        ]);
                        await withSigner(
                            this.erc20RootVaultGovernance.address,
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
                                            [startNft]
                                        )
                                ).to.be.revertedWith(Exceptions.DUPLICATE);
                            }
                        );
                    });
                });

                describe("when subvaultNFT does not support interface", () => {
                    it(`reverts with ${Exceptions.INVALID_INTERFACE}`, async () => {
                        const startNft = await this.vaultRegistry.vaultsCount();
                        await withSigner(
                            this.erc20RootVaultGovernance.address,
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
                                            [startNft]
                                        )
                                ).to.be.revertedWith(
                                    Exceptions.INVALID_INTERFACE
                                );
                            }
                        );
                    });
                });
            });
        });

        const preprocessSigner = async (
            signer: SignerWithAddress,
            amount: BigNumber
        ) => {
            await mint("USDC", signer.address, amount);
            await mint("WETH", signer.address, amount);
            await this.usdc
                .connect(signer)
                .approve(this.subject.address, amount);
            await this.weth
                .connect(signer)
                .approve(this.subject.address, amount);
            await this.subject
                .connect(this.admin)
                .addDepositorsToAllowlist([signer.address]);
        };

        const setupZeroPerformanceFee = async () => {
            var governance: IERC20RootVaultGovernance =
                await ethers.getContractAt(
                    "IERC20RootVaultGovernance",
                    await this.subject.vaultGovernance()
                );

            const nftIndex = await this.subject.nft();
            const {
                strategyTreasury: strategyTreasury,
                strategyPerformanceTreasury: strategyPerformanceTreasury,
            } = await governance.delayedStrategyParams(nftIndex);

            await governance
                .connect(this.admin)
                .stageDelayedStrategyParams(nftIndex, {
                    strategyTreasury: strategyTreasury,
                    strategyPerformanceTreasury: strategyPerformanceTreasury,
                    privateVault: true,
                    managementFee: BigNumber.from(3000),
                    performanceFee: BigNumber.from(0),
                    depositCallbackAddress: ethers.constants.AddressZero,
                    withdrawCallbackAddress: ethers.constants.AddressZero,
                } as DelayedStrategyParamsStruct);
            await sleep(this.governanceDelay);
            await governance
                .connect(this.admin)
                .commitDelayedStrategyParams(nftIndex);
        };

        const setupLpCallback = async (mode: number) => {
            const { deployments } = hre;
            const { deploy } = deployments;
            const { address: lpCallbackAddress } = await deploy(
                "MockLpCallback",
                {
                    from: this.deployer.address,
                    args: [BigNumber.from(mode)],
                    log: true,
                    autoMine: true,
                }
            );

            const lpCallback: MockLpCallback = await ethers.getContractAt(
                "MockLpCallback",
                lpCallbackAddress
            );
            var governance: IERC20RootVaultGovernance =
                await ethers.getContractAt(
                    "IERC20RootVaultGovernance",
                    await this.subject.vaultGovernance()
                );

            const nftIndex = await this.subject.nft();
            const { strategyTreasury: strategyTreasury } =
                await governance.delayedStrategyParams(nftIndex);
            const { strategyPerformanceTreasury: strategyPerformanceTreasury } =
                await governance.delayedStrategyParams(nftIndex);

            await governance
                .connect(this.admin)
                .stageDelayedStrategyParams(nftIndex, {
                    strategyTreasury: strategyTreasury,
                    strategyPerformanceTreasury: strategyPerformanceTreasury,
                    privateVault: true,
                    managementFee: BigNumber.from(3000),
                    performanceFee: BigNumber.from(3000),
                    depositCallbackAddress: lpCallback.address,
                    withdrawCallbackAddress: lpCallback.address,
                } as DelayedStrategyParamsStruct);
            await sleep(this.governanceDelay);
            await governance
                .connect(this.admin)
                .commitDelayedStrategyParams(nftIndex);
            return lpCallback;
        };

        enum WithdrawCallbackMode {
            NO_ERROR = 0,
            EMPTY_ERROR = 1,
            NON_EMPTY_ERROR = 2,
        }

        describe("#deposit", () => {
            const MIN_FIRST_DEPOSIT = BigNumber.from(10001);
            const DEFAULT_MIN_LP_TOKEN = BigNumber.from(1);

            beforeEach(async () => {
                await this.erc20RootVaultGovernance
                    .connect(this.admin)
                    .setOperatorParams({
                        disableDeposit: false,
                    });
            });

            it("emits Deposit event", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await preprocessSigner(signer, MIN_FIRST_DEPOSIT);
                    await expect(
                        this.subject
                            .connect(signer)
                            .deposit(
                                [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            )
                    ).to.emit(this.subject, "Deposit");
                });
            });

            const setupTreasure = async () => {
                let erc20Factory = await ethers.getContractFactory(
                    "ERC20Token"
                );
                var { address: treasureAddress } = await erc20Factory.deploy();
                var governance: IERC20RootVaultGovernance =
                    await ethers.getContractAt(
                        "IERC20RootVaultGovernance",
                        await this.subject.vaultGovernance()
                    );

                const nftIndex = await this.subject.nft();
                const { strategyTreasury: strategyTreasury } =
                    await governance.delayedStrategyParams(nftIndex);

                await governance
                    .connect(this.admin)
                    .stageDelayedStrategyParams(nftIndex, {
                        strategyTreasury: strategyTreasury,
                        strategyPerformanceTreasury: treasureAddress,
                        privateVault: true,
                        managementFee: BigNumber.from(3000),
                        performanceFee: BigNumber.from(0),
                        depositCallbackAddress: ethers.constants.AddressZero,
                        withdrawCallbackAddress: ethers.constants.AddressZero,
                    } as DelayedStrategyParamsStruct);
                await sleep(this.governanceDelay);
                await governance
                    .connect(this.admin)
                    .commitDelayedStrategyParams(nftIndex);
                return treasureAddress;
            };

            const getTreasureBalanceForSigner = async (
                treasureAddress: string,
                signer: string
            ) => {
                const treasure: ERC20Token = await ethers.getContractAt(
                    "ERC20Token",
                    treasureAddress
                );
                return treasure.balanceOf(signer);
            };

            describe("edge cases:", () => {
                describe("when lpPriceD18 <= hwmsD18", () => {
                    it("do not charge performance fees", async () => {
                        const treasureAddress = await setupTreasure();
                        await this.erc20RootVaultGovernance
                            .connect(this.admin)
                            .stageDelayedProtocolParams({
                                managementFeeChargeDelay: 0,
                                oracle: this.mellowOracle.address,
                            } as DelayedProtocolParamsStruct);

                        await sleep(this.governanceDelay);
                        await this.erc20RootVaultGovernance
                            .connect(this.admin)
                            .commitDelayedProtocolParams();

                        var signer = await addSigner(randomAddress());
                        const treasuryBalanceBefore =
                            await getTreasureBalanceForSigner(
                                treasureAddress,
                                signer.address
                            );
                        const amount = BigNumber.from(10)
                            .pow(21)
                            .mul(3)
                            .add(MIN_FIRST_DEPOSIT);
                        const defaultDepositAmount = BigNumber.from(10).pow(14);
                        await preprocessSigner(signer, amount);
                        await this.subject
                            .connect(signer)
                            .deposit(
                                [
                                    defaultDepositAmount.mul(32),
                                    defaultDepositAmount.mul(32),
                                ],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            );

                        await this.subject
                            .connect(signer)
                            .deposit(
                                [
                                    defaultDepositAmount.mul(32),
                                    defaultDepositAmount.mul(32),
                                ],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            );

                        await this.subject
                            .connect(signer)
                            .deposit(
                                [
                                    defaultDepositAmount.mul(30),
                                    defaultDepositAmount.mul(30),
                                ],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            );

                        const treasuryBalanceAfter =
                            await getTreasureBalanceForSigner(
                                treasureAddress,
                                signer.address
                            );
                        expect(treasuryBalanceBefore).to.be.eq(
                            treasuryBalanceAfter
                        );
                    });
                });

                describe("when performance fee is zero", () => {
                    it("do not charge performance fees", async () => {
                        const treasureAddress = await setupTreasure();
                        await this.erc20RootVaultGovernance
                            .connect(this.admin)
                            .stageDelayedProtocolParams({
                                managementFeeChargeDelay: 0,
                                oracle: this.mellowOracle.address,
                            } as DelayedProtocolParamsStruct);

                        await sleep(this.governanceDelay);
                        await this.erc20RootVaultGovernance
                            .connect(this.admin)
                            .commitDelayedProtocolParams();

                        var signer = await addSigner(randomAddress());
                        const treasuryBalanceBefore =
                            await getTreasureBalanceForSigner(
                                treasureAddress,
                                signer.address
                            );
                        const amount = BigNumber.from(10)
                            .pow(21)
                            .mul(3)
                            .add(MIN_FIRST_DEPOSIT);
                        const defaultDepositAmount = BigNumber.from(10).pow(14);
                        await preprocessSigner(signer, amount);
                        await setupZeroPerformanceFee();
                        await this.subject
                            .connect(signer)
                            .deposit(
                                [
                                    defaultDepositAmount.mul(32),
                                    defaultDepositAmount.mul(32),
                                ],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            );

                        await this.subject
                            .connect(signer)
                            .deposit(
                                [
                                    defaultDepositAmount.mul(32),
                                    defaultDepositAmount.mul(32),
                                ],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            );

                        await this.subject
                            .connect(signer)
                            .deposit(
                                [
                                    defaultDepositAmount.mul(30),
                                    defaultDepositAmount.mul(30),
                                ],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            );
                        await setupLpCallback(WithdrawCallbackMode.NO_ERROR);

                        const treasuryBalanceAfter =
                            await getTreasureBalanceForSigner(
                                treasureAddress,
                                signer.address
                            );
                        expect(treasuryBalanceBefore).to.be.eq(
                            treasuryBalanceAfter
                        );
                    });
                });

                describe("when deposit is disabled", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.erc20RootVaultGovernance
                            .connect(this.admin)
                            .setOperatorParams({
                                disableDeposit: true,
                            });
                        await expect(
                            this.subject.deposit([], DEFAULT_MIN_LP_TOKEN, [])
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                describe("when there is no depositor in allow list", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.subject
                            .connect(this.admin)
                            .removeDepositorsFromAllowlist([
                                this.deployer.address,
                            ]);
                        await expect(
                            this.subject.deposit(
                                [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                describe("when there is a private vault in delayedStrategyParams", () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.subject
                            .connect(this.admin)
                            .removeDepositorsFromAllowlist([
                                this.deployer.address,
                            ]);
                        const nftIndex = await this.subject.nft();
                        {
                            var subvaultNfts =
                                await this.subject.subvaultNfts();
                            expect(subvaultNfts).to.be.not.empty;
                            var index = 0;
                            subvaultNfts.forEach(async (subvaultNft) => {
                                expect(
                                    await this.subject.subvaultAt(
                                        BigNumber.from(index)
                                    )
                                ).not.to.be.eq(ethers.constants.AddressZero);
                                expect(
                                    await this.subject.hasSubvault(subvaultNft)
                                ).to.be.true;
                                expect(
                                    await this.subject.subvaultOneBasedIndex(
                                        subvaultNft
                                    )
                                ).not.to.be.eq(ethers.constants.AddressZero);
                                index += 1;
                            });
                        }
                        const params = {
                            strategyTreasury: randomAddress(),
                            strategyPerformanceTreasury: randomAddress(),
                            privateVault: true,
                            managementFee: BigNumber.from(randomInt(10 ** 6)),
                            performanceFee: BigNumber.from(randomInt(10 ** 6)),
                            depositCallbackAddress:
                                ethers.constants.AddressZero,
                            withdrawCallbackAddress:
                                ethers.constants.AddressZero,
                        };
                        await this.erc20RootVaultGovernance
                            .connect(this.admin)
                            .stageDelayedStrategyParams(nftIndex, params);
                        await sleep(this.governanceDelay);
                        await this.erc20RootVaultGovernance
                            .connect(this.admin)
                            .commitDelayedStrategyParams(nftIndex);

                        await expect(
                            this.subject.deposit(
                                [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                DEFAULT_MIN_LP_TOKEN,
                                []
                            )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });

                describe("when minLpTokens is greater than lpAmount", () => {
                    it(`reverts with ${Exceptions.LIMIT_UNDERFLOW}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await preprocessSigner(signer, MIN_FIRST_DEPOSIT);
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .deposit(
                                        [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                        MIN_FIRST_DEPOSIT.mul(10),
                                        []
                                    )
                            ).to.be.revertedWith(Exceptions.LIMIT_UNDERFLOW);
                        });
                    });
                });

                describe("when tokenAmounts is less than or equal to FIRST_DEPOSIT_LIMIT", () => {
                    it(`reverts with ${Exceptions.LIMIT_UNDERFLOW}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await preprocessSigner(signer, MIN_FIRST_DEPOSIT);
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .deposit(
                                        [BigNumber.from(0), BigNumber.from(0)],
                                        MIN_FIRST_DEPOSIT,
                                        []
                                    )
                            ).to.be.revertedWith(Exceptions.LIMIT_UNDERFLOW);
                        });
                    });
                });

                describe("when depositCallback Address is set", () => {
                    it("emits deposits callback called", async () => {
                        var lpCallback = await setupLpCallback(
                            WithdrawCallbackMode.NO_ERROR
                        );

                        await preprocessSigner(
                            this.deployer,
                            MIN_FIRST_DEPOSIT
                        );
                        await expect(
                            this.subject
                                .connect(this.deployer)
                                .deposit(
                                    [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                    DEFAULT_MIN_LP_TOKEN,
                                    []
                                )
                        ).to.emit(lpCallback, "DepositCallbackCalled");
                    });
                });

                describe("when lpAmount is zero", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await preprocessSigner(signer, MIN_FIRST_DEPOSIT);
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .deposit(
                                        [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                        DEFAULT_MIN_LP_TOKEN,
                                        []
                                    )
                            ).not.to.be.reverted;

                            await expect(
                                this.subject
                                    .connect(signer)
                                    .deposit(
                                        [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                        BigNumber.from(0),
                                        []
                                    )
                            ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                        });
                    });
                });

                describe("when sum of lpAmount and sender balance is greater than tokenLimitPerAddress", () => {
                    it(`reverts with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            const nftIndex = await this.subject.nft();
                            await preprocessSigner(signer, MIN_FIRST_DEPOSIT);
                            await this.erc20RootVaultGovernance
                                .connect(this.admin)
                                .setStrategyParams(nftIndex, {
                                    tokenLimitPerAddress: BigNumber.from(0),
                                    tokenLimit: BigNumber.from(0),
                                });

                            await expect(
                                this.subject
                                    .connect(signer)
                                    .deposit(
                                        [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                        BigNumber.from(1),
                                        []
                                    )
                            ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                        });
                    });
                });

                describe("when sum of lpAmount and totalSupply is greater than tokenLimit", () => {
                    it(`reverts with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            const nftIndex = await this.subject.nft();
                            await preprocessSigner(signer, MIN_FIRST_DEPOSIT);
                            await this.erc20RootVaultGovernance
                                .connect(this.admin)
                                .setStrategyParams(BigNumber.from(nftIndex), {
                                    tokenLimitPerAddress:
                                        MIN_FIRST_DEPOSIT.mul(10),
                                    tokenLimit: BigNumber.from(0),
                                });

                            await expect(
                                this.subject
                                    .connect(signer)
                                    .deposit(
                                        [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                        DEFAULT_MIN_LP_TOKEN,
                                        []
                                    )
                            ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                        });
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await preprocessSigner(
                            signer,
                            BigNumber.from(10).pow(18)
                        );
                        await expect(
                            this.subject
                                .connect(signer)
                                .deposit(
                                    [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                    DEFAULT_MIN_LP_TOKEN,
                                    []
                                )
                        ).to.emit(this.subject, "Deposit");
                    });
                });
            });
        });

        describe("#withdraw", () => {
            const MIN_FIRST_DEPOSIT = BigNumber.from(10001);
            const DEFAULT_MIN_LP_TOKEN = BigNumber.from(1);
            const NON_EMPTY_DEFAULT_OPTIONS = [[], []];

            it("emits Withdraw event", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await preprocessSigner(signer, MIN_FIRST_DEPOSIT.pow(3));
                    await expect(
                        this.subject
                            .connect(signer)
                            .deposit(
                                [
                                    MIN_FIRST_DEPOSIT.pow(3),
                                    MIN_FIRST_DEPOSIT.pow(3),
                                ],
                                BigNumber.from(0),
                                []
                            )
                    ).not.to.be.reverted;
                    await expect(
                        this.subject
                            .connect(signer)
                            .withdraw(
                                randomAddress(),
                                BigNumber.from(1),
                                [DEFAULT_MIN_LP_TOKEN, DEFAULT_MIN_LP_TOKEN],
                                NON_EMPTY_DEFAULT_OPTIONS
                            )
                    ).to.emit(this.subject, "Withdraw");
                });
            });

            describe("edge cases:", () => {
                describe("when total supply is 0", () => {
                    it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .withdraw(
                                        randomAddress(),
                                        DEFAULT_MIN_LP_TOKEN,
                                        [],
                                        []
                                    )
                            ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                        });
                    });
                });

                describe("when length of vaultsOptions and length of _subvaultNfts are different", () => {
                    it(`reverts with ${Exceptions.INVALID_LENGTH}`, async () => {
                        await preprocessSigner(this.admin, MIN_FIRST_DEPOSIT);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .deposit(
                                    [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                    BigNumber.from(0),
                                    []
                                )
                        ).not.to.be.reverted;

                        await expect(
                            this.subject.withdraw(
                                randomAddress(),
                                DEFAULT_MIN_LP_TOKEN,
                                [],
                                []
                            )
                        ).to.be.revertedWith(Exceptions.INVALID_LENGTH);
                    });
                });

                describe("when withdrawn is larger than protocol governance withdraw limit for vault token", () => {
                    it(`reverts with ${Exceptions.LIMIT_OVERFLOW}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await preprocessSigner(
                                signer,
                                MIN_FIRST_DEPOSIT.pow(3)
                            );
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .deposit(
                                        [
                                            MIN_FIRST_DEPOSIT.pow(3),
                                            MIN_FIRST_DEPOSIT.pow(3),
                                        ],
                                        BigNumber.from(0),
                                        []
                                    )
                            ).not.to.be.reverted;
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .withdraw(
                                        randomAddress(),
                                        MIN_FIRST_DEPOSIT,
                                        [
                                            DEFAULT_MIN_LP_TOKEN,
                                            DEFAULT_MIN_LP_TOKEN,
                                        ],
                                        NON_EMPTY_DEFAULT_OPTIONS
                                    )
                            ).to.be.revertedWith(Exceptions.LIMIT_OVERFLOW);
                        });
                    });
                });

                describe("When address of lpCallback is not null", () => {
                    it("emits withdrawCallback", async () => {
                        await preprocessSigner(this.admin, MIN_FIRST_DEPOSIT);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .deposit(
                                    [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                    BigNumber.from(0),
                                    []
                                )
                        ).not.to.be.reverted;

                        var lpCallback = await setupLpCallback(
                            WithdrawCallbackMode.NO_ERROR
                        );

                        await expect(
                            this.subject.withdraw(
                                randomAddress(),
                                BigNumber.from(0),
                                [BigNumber.from(0), BigNumber.from(0)],
                                NON_EMPTY_DEFAULT_OPTIONS
                            )
                        ).to.emit(lpCallback, "WithdrawCallbackCalled");
                    });
                });

                describe("When address of lpCallback is not null and lpCallback throws empty error", () => {
                    it("emits WithdrawCallbackLog", async () => {
                        await preprocessSigner(this.admin, MIN_FIRST_DEPOSIT);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .deposit(
                                    [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                    BigNumber.from(0),
                                    []
                                )
                        ).not.to.be.reverted;

                        await setupLpCallback(WithdrawCallbackMode.EMPTY_ERROR);

                        await expect(
                            this.subject.withdraw(
                                randomAddress(),
                                BigNumber.from(0),
                                [BigNumber.from(0), BigNumber.from(0)],
                                NON_EMPTY_DEFAULT_OPTIONS
                            )
                        ).to.emit(this.subject, "WithdrawCallbackLog");
                    });
                });

                describe("When address of lpCallback is not null and lpCallback throws non empty error", () => {
                    it("emits WithdrawCallbackLog", async () => {
                        await preprocessSigner(this.admin, MIN_FIRST_DEPOSIT);
                        await expect(
                            this.subject
                                .connect(this.admin)
                                .deposit(
                                    [MIN_FIRST_DEPOSIT, MIN_FIRST_DEPOSIT],
                                    BigNumber.from(0),
                                    []
                                )
                        ).not.to.be.reverted;

                        await setupLpCallback(
                            WithdrawCallbackMode.NON_EMPTY_ERROR
                        );

                        await expect(
                            this.subject.withdraw(
                                randomAddress(),
                                BigNumber.from(0),
                                [BigNumber.from(0), BigNumber.from(0)],
                                NON_EMPTY_DEFAULT_OPTIONS
                            )
                        ).to.emit(this.subject, "WithdrawCallbackLog");
                    });
                });
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await preprocessSigner(
                            signer,
                            MIN_FIRST_DEPOSIT.pow(3)
                        );
                        await expect(
                            this.subject
                                .connect(signer)
                                .deposit(
                                    [
                                        MIN_FIRST_DEPOSIT.pow(3),
                                        MIN_FIRST_DEPOSIT.pow(3),
                                    ],
                                    BigNumber.from(0),
                                    []
                                )
                        ).not.to.be.reverted;

                        await expect(
                            this.subject
                                .connect(signer)
                                .withdraw(
                                    randomAddress(),
                                    BigNumber.from(1),
                                    [BigNumber.from(1), BigNumber.from(1)],
                                    NON_EMPTY_DEFAULT_OPTIONS
                                )
                        ).to.emit(this.subject, "Withdraw");
                    });
                });
            });
        });
    }
);
