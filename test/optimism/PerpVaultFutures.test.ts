import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    sleep,
    withSigner,
    randomAddress,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault, ERC20Vault, PerpFuturesVault } from "../types";
import { combineVaults, setupVault } from "../../deploy/0000_utils";

import { abi as IPerpInternalVault } from "../helpers/PerpVaultABI.json";
import { abi as IClearingHouse } from "../helpers/ClearingHouseABI.json";
import { pre } from "fast-check";
import { expect } from "chai";
import { uint256 } from "../library/property";
import { Address } from "hardhat-deploy/types";
import Exceptions from "../library/Exceptions";
import { integrationVaultBehavior } from "../behaviors/integrationVault";

import {
    PERP_VAULT_INTERFACE_ID,
    INTEGRATION_VAULT_INTERFACE_ID,
} from "../library/Constants";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<PerpFuturesVault, DeployOptions, CustomContext>(
    "Optimism__PerpFuturesVault",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { read } = deployments;

                    const { curveRouter } = await getNamedAccounts();
                    this.curveRouter = curveRouter;
                    this.preparePush = async () => {
                        await sleep(0);
                    };

                    const tokens = [this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let perpVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;

                    let veth = "0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB";
                    this.leverage = 4;

                    await setupVault(hre, perpVaultNft, "PerpVaultGovernance", {
                        createVaultArgs: [
                            this.deployer.address,
                            veth,
                            BigNumber.from(10).pow(9).mul(this.leverage),
                            true,
                        ],
                    });
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
                        [erc20VaultNft, perpVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );
                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );
                    const perpVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        perpVaultNft
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
                        "PerpFuturesVault",
                        perpVault
                    );

                    this.erc20RootVault = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );

                    const contract = await ethers.getContractAt(
                        "IERC20",
                        this.usdc.address
                    );

                    this.mintUsd = async (addr: Address, x: BigNumber) => {
                        const prevBalance = await contract.balanceOf(addr);
                        await mint("OUSDC", addr, x);
                        await this.usdc.approve(
                            addr,
                            ethers.constants.MaxUint256
                        );
                        const newBalance = await contract.balanceOf(addr);
                        expect(prevBalance).to.be.lt(newBalance);
                    };

                    for (let address of [
                        this.deployer.address,
                        this.subject.address,
                    ]) {
                        await this.mintUsd(
                            address,
                            BigNumber.from(10).pow(6).mul(3000)
                        );
                    }

                    this.isClose = async (
                        x: BigNumber,
                        y: BigNumber,
                        closeMeasure: BigNumber
                    ) => {
                        const delta = x.sub(y).abs();
                        const max = x.gt(y) ? x : y;
                        const deltaM = delta.mul(closeMeasure);

                        return max.gt(deltaM);
                    };

                    this.pushIntoVault = async (x: BigNumber) => {
                        const tx = await this.subject.push(
                            [this.usdc.address],
                            [x],
                            encodeToBytes(
                                ["uint256", "uint256"],
                                [ethers.constants.MaxUint256, 0]
                            )
                        );
                        return tx;
                    };

                    this.pullFromVault = async (x: BigNumber) => {
                        await this.subject.pull(
                            this.erc20Vault.address,
                            [this.usdc.address],
                            [x],
                            encodeToBytes(
                                ["uint256", "uint256"],
                                [ethers.constants.MaxUint256, 0]
                            )
                        );
                    };

                    this.checkTvlEqualsToSupposed = async (
                        x: BigNumber,
                        isMinTvlMeant: boolean
                    ) => {
                        const tvl = await this.subject.tvl();

                        let expected = x.sub(x.mul(this.leverage).div(1000)); //minus trade fees 0.1%
                        if (isMinTvlMeant) {
                            const isSpotClose = await this.isClose(
                                expected,
                                tvl[0][0],
                                BigNumber.from(100)
                            );
                            expect(isSpotClose).to.be.true;
                        } else {
                            const isSpotClose = await this.isClose(
                                expected,
                                tvl[1][0],
                                BigNumber.from(100)
                            );
                            expect(isSpotClose).to.be.true;
                        }
                    };

                    this.sendTransactionToPoolToSweepPrice = async (
                        long: boolean
                    ) => {
                        const { perpVault, vethAddress } =
                            await getNamedAccounts();
                        const perpVaultContract = await ethers.getContractAt(
                            IPerpInternalVault,
                            perpVault
                        );
                        await this.mintUsd(
                            this.deployer.address,
                            BigNumber.from(10).pow(10).mul(5)
                        );
                        await this.usdc.approve(
                            perpVault,
                            ethers.constants.MaxUint256
                        );
                        await perpVaultContract.deposit(
                            this.usdc.address,
                            BigNumber.from(10).pow(10).mul(5)
                        );

                        const clearingHouse =
                            await this.subject.clearingHouse();

                        const clearingHouseContract =
                            await ethers.getContractAt(
                                IClearingHouse,
                                clearingHouse
                            );

                        await clearingHouseContract.openPosition({
                            baseToken: vethAddress,
                            isBaseToQuote: !long,
                            isExactInput: long,
                            amount: BigNumber.from(10).pow(22).mul(5),
                            oppositeAmountBound: 0,
                            deadline: ethers.constants.MaxUint256,
                            sqrtPriceLimitX96: 0,
                            referralCode:
                                "0x0000000000000000000000000000000000000000000000000000000000000000",
                        });
                    };

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#tvl", () => {
            it("zero tvl when nothing is done", async () => {
                const tvl = await this.subject.tvl();
                expect(tvl[0][0]).to.be.eq(BigNumber.from(0));
            });

            it("just deposited if no actions to pools are taken and opposite is actions are taken", async () => {
                await this.subject.updateLeverage(
                    0,
                    true,
                    ethers.constants.MaxUint256,
                    0
                );

                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4));

                const tvl = await this.subject.tvl();
                expect(tvl[0][0]).to.be.eq(BigNumber.from(10).pow(6).mul(4));
                expect(tvl[1][0]).to.be.eq(BigNumber.from(10).pow(6).mul(4));
                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(5),
                    true,
                    ethers.constants.MaxUint256,
                    0
                );
                const newTvl = await this.subject.tvl();

                expect(newTvl[0][0]).not.to.be.eq(
                    BigNumber.from(10).pow(6).mul(4)
                );
                expect(newTvl[1][0]).not.to.be.eq(
                    BigNumber.from(10).pow(6).mul(4)
                );
            });

            it("minTvl equals to pure capital (in case of long, because we assume on the forked block the price was less than the average)", async () => {
                this.pushIntoVault(BigNumber.from(10).pow(6).mul(4));
                const W = await this.subject.getPositionSize();
                expect(W).to.be.gt(0);
                await this.checkTvlEqualsToSupposed(
                    BigNumber.from(10).pow(6).mul(4),
                    true
                );

                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(2));
                await this.checkTvlEqualsToSupposed(
                    BigNumber.from(10).pow(6).mul(6),
                    true
                );

                await this.pullFromVault(BigNumber.from(10).pow(6));
                await this.checkTvlEqualsToSupposed(
                    BigNumber.from(10).pow(6).mul(5),
                    true
                );
            });

            it("maxTvl equals to pure capital (in case of long, because we assume on the forked block the price was less than the average)", async () => {
                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(5),
                    false,
                    ethers.constants.MaxUint256,
                    0
                ); // change sentiment to short
                this.pushIntoVault(BigNumber.from(10).pow(6).mul(4));
                await this.checkTvlEqualsToSupposed(
                    BigNumber.from(10).pow(6).mul(4),
                    false
                );
            });

            it("tvl rises when capital rises (in case of long)", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether

                const oldTvl = await this.subject.tvl();

                await this.sendTransactionToPoolToSweepPrice(true);

                const newTvl = await this.subject.tvl();

                expect(oldTvl[0][0]).to.be.lt(newTvl[0][0]);
                expect(oldTvl[1][0]).to.be.lt(newTvl[1][0]);
            });

            it("tvl plummets when base token plummets (in case of long)", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether

                const oldTvl = await this.subject.tvl();

                await this.sendTransactionToPoolToSweepPrice(false);

                const newTvl = await this.subject.tvl();

                expect(oldTvl[0][0]).to.be.gt(newTvl[0][0]);
                expect(oldTvl[1][0]).to.be.gt(newTvl[1][0]);
            });

            it("tvl rises when base token plummets (in case of short)", async () => {
                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(5),
                    false,
                    ethers.constants.MaxUint256,
                    0
                ); // change sentiment to short

                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // shorting ether

                const oldTvl = await this.subject.tvl();

                await this.sendTransactionToPoolToSweepPrice(false);

                const newTvl = await this.subject.tvl();

                expect(oldTvl[0][0]).to.be.lt(newTvl[0][0]);
                expect(oldTvl[1][0]).to.be.lt(newTvl[1][0]);
            });

            it("tvl plummets when base token rises (in case of short)", async () => {
                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(5),
                    false,
                    ethers.constants.MaxUint256,
                    0
                ); // change sentiment to short

                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // shorting ether

                const oldTvl = await this.subject.tvl();

                await this.sendTransactionToPoolToSweepPrice(true);

                const newTvl = await this.subject.tvl();

                expect(oldTvl[0][0]).to.be.gt(newTvl[0][0]);
                expect(oldTvl[1][0]).to.be.gt(newTvl[1][0]);
            });

            it("tvl goes to zero in case of sharp decline", async () => {
                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(9),
                    true,
                    ethers.constants.MaxUint256,
                    0
                ); //max possible leverage
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether

                const oldTvl = await this.subject.tvl();

                for (let i = 0; i < 11; ++i) {
                    await this.sendTransactionToPoolToSweepPrice(false);
                }

                const newTvl = await this.subject.tvl();
                expect(newTvl[1][0].mul(100)).to.be.gt(oldTvl[1][0].mul(95)); // proves the state isn't subject to a manipulation
                expect(newTvl[0][0]).to.be.eq(BigNumber.from(0));
            });

            it("one of tvls equals to final after position closing", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether
                await this.sendTransactionToPoolToSweepPrice(true);

                const oldTvl = await this.subject.tvl();
                await this.subject.closePosition(
                    ethers.constants.MaxUint256,
                    0
                );

                const newTvl = await this.subject.tvl();

                expect(newTvl[0][0]).to.be.eq(newTvl[1][0]);

                let isSpotClose =
                    (await this.isClose(oldTvl[0][0], newTvl[0][0], 100)) ||
                    (await this.isClose(oldTvl[1][0], newTvl[0][0], 100));

                expect(isSpotClose).to.be.true;
            });

            it("access control", async () => {
                it("anyone can call", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(this.subject.connect(s).tvl()).to.not.be
                            .reverted;
                    });
                });
            });
        });

        describe("#getPositionSize", () => {
            it("positionSize equals zero when no position opened", async () => {
                const positionSize = await this.subject.getPositionSize();
                expect(positionSize).to.be.eq(0);
            });

            it("positionSize equals to the amount of ether got (long)", async () => {
                const tx = await this.pushIntoVault(
                    BigNumber.from(10).pow(6).mul(4)
                ); // longing ether
                const receipt = await tx.wait();
                let etherAmount = 0;
                for (const event of receipt.events) {
                    if (event.event == "TradePassed") {
                        etherAmount = event.args[2];
                    }
                }
                const positionSize = await this.subject.getPositionSize();
                expect(positionSize).to.be.eq(etherAmount);
                expect(positionSize).to.be.gt(BigNumber.from(0));
            });

            it("positionSize equals to the amount of ether got (short)", async () => {
                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(5),
                    false,
                    ethers.constants.MaxUint256,
                    0
                ); // change sentiment to short

                const tx = await this.pushIntoVault(
                    BigNumber.from(10).pow(6).mul(4)
                ); // longing ether
                const receipt = await tx.wait();
                let etherAmount = 0;
                for (const event of receipt.events) {
                    if (event.event == "TradePassed") {
                        etherAmount = event.args[2];
                    }
                }
                const positionSize = await this.subject.getPositionSize();

                expect(positionSize.add(etherAmount)).to.be.eq(0);
                expect(positionSize).to.be.lt(BigNumber.from(0));
            });

            it("positionSize is zero after position closed (long)", async () => {
                const tx = await this.pushIntoVault(
                    BigNumber.from(10).pow(6).mul(4)
                ); // longing ether
                const oldSize = await this.subject.getPositionSize();
                expect(oldSize).to.be.gt(BigNumber.from(0));
                await this.subject.closePosition(
                    ethers.constants.MaxUint256,
                    0
                );
                const newSize = await this.subject.getPositionSize();
                expect(newSize).to.be.eq(BigNumber.from(0));
            });

            it("positionSize is zero after position closed (short)", async () => {
                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(5),
                    false,
                    ethers.constants.MaxUint256,
                    0
                );

                const tx = await this.pushIntoVault(
                    BigNumber.from(10).pow(6).mul(4)
                ); // longing ether
                const oldSize = await this.subject.getPositionSize();
                expect(oldSize).to.be.lt(BigNumber.from(0));
                await this.subject.closePosition(
                    ethers.constants.MaxUint256,
                    0
                );
                const newSize = await this.subject.getPositionSize();
                expect(newSize).to.be.eq(BigNumber.from(0));
            });

            it("position size is updating in both sides", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether
                const veryOldSize = await this.subject.getPositionSize();

                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4));
                const oldSize = await this.subject.getPositionSize();

                await this.pullFromVault(BigNumber.from(10).pow(6));
                const newSize = await this.subject.getPositionSize();

                expect(veryOldSize).to.be.lt(oldSize);
                expect(veryOldSize).to.be.lt(newSize);
                expect(oldSize).to.be.gt(newSize);
            });

            it("access control", async () => {
                it("anyone can call", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(this.subject.connect(s).getPositionSize())
                            .to.not.be.reverted;
                    });
                });
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${PERP_VAULT_INTERFACE_ID} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        PERP_VAULT_INTERFACE_ID
                    )
                ).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .supportsInterface(
                                    INTEGRATION_VAULT_INTERFACE_ID
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

                const { vethAddress } = await getNamedAccounts();
                this.veth = vethAddress;
            });

            it("emits Initialized event", async () => {
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    this.veth,
                                    BigNumber.from(10).pow(9).mul(5),
                                    true
                                )
                        ).to.emit(this.subject, "Initialized");
                    }
                );
            });

            it("initializes contract successfully in case of long", async () => {
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    this.veth,
                                    BigNumber.from(10).pow(9).mul(5),
                                    true
                                )
                        ).not.to.be.reverted;
                    }
                );
            });

            it("initializes contract successfully in case of short", async () => {
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    this.veth,
                                    BigNumber.from(10).pow(9).mul(5),
                                    false
                                )
                        ).not.to.be.reverted;
                    }
                );
            });

            it("reverts when a token market is closed", async () => {
                const lunaAddress =
                    "0xB24F50Dd9918934AB2228bE7A097411ca28F6C14";
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    lunaAddress,
                                    BigNumber.from(10).pow(9).mul(5),
                                    true
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                    }
                );
            });

            it("okay with some third token", async () => {
                const maticAddress =
                    "0xBe5de48197fc974600929196239E264EcB703eE8";
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    maticAddress,
                                    BigNumber.from(10).pow(9).mul(5),
                                    true
                                )
                        ).not.to.be.reverted;
                    }
                );
            });

            it("reverts when no Perp token", async () => {
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    randomAddress(),
                                    BigNumber.from(10).pow(9).mul(5),
                                    true
                                )
                        ).to.be.reverted;
                    }
                );
            });

            it("revertes with too large leverage multiplier", async () => {
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    this.veth,
                                    BigNumber.from(10).pow(10),
                                    true
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_VALUE);

                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    this.veth,
                                    BigNumber.from(10).pow(10),
                                    false
                                )
                        ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                    }
                );
            });

            it("okay with zero leverage multiplier", async () => {
                await withSigner(
                    this.perpVaultGovernance.address,
                    async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .initialize(
                                    this.nft,
                                    this.veth,
                                    BigNumber.from(0),
                                    true
                                )
                        ).not.to.be.reverted;
                    }
                );
            });

            it("access control", async () => {
                it("not allowed: any address", async () => {
                    await expect(
                        this.subject.initialize(
                            this.nft,
                            this.veth,
                            BigNumber.from(0),
                            true
                        )
                    ).to.be.reverted;
                });
            });

            describe("when vault's nft is not 0", () => {
                it(`reverts with ${Exceptions.INIT}`, async () => {
                    await ethers.provider.send("hardhat_setStorageAt", [
                        this.subject.address,
                        "0x4", // address of _nft
                        "0x0000000000000000000000000000000000000000000000000000000000000007",
                    ]);
                    await withSigner(
                        this.perpVaultGovernance.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .initialize(
                                        0,
                                        this.veth,
                                        BigNumber.from(0),
                                        true
                                    )
                            ).to.be.revertedWith(Exceptions.INIT);
                        }
                    );
                });
            });

            describe("when setting zero nft", () => {
                it(`reverts with ${Exceptions.VALUE_ZERO}`, async () => {
                    await withSigner(
                        this.perpVaultGovernance.address,
                        async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .initialize(
                                        0,
                                        this.veth,
                                        BigNumber.from(0),
                                        true
                                    )
                            ).to.be.revertedWith(Exceptions.VALUE_ZERO);
                        }
                    );
                });
            });
        });

        describe("#updateLeverage", () => {
            it("call with the same parameter goes okay", async () => {
                await expect(
                    this.subject.updateLeverage(
                        BigNumber.from(10).pow(9).mul(5),
                        true,
                        ethers.constants.MaxUint256,
                        0
                    )
                ).not.to.be.reverted;
            });

            it("revertes with too large leverage multiplier (long & short)", async () => {
                await expect(
                    this.subject.updateLeverage(
                        BigNumber.from(10).pow(10),
                        true,
                        ethers.constants.MaxUint256,
                        0
                    )
                ).to.be.revertedWith(Exceptions.INVALID_VALUE);

                await expect(
                    this.subject.updateLeverage(
                        BigNumber.from(10).pow(10),
                        false,
                        ethers.constants.MaxUint256,
                        0
                    )
                ).to.be.revertedWith(Exceptions.INVALID_VALUE);
            });

            it("emits UpdatedLeverage event", async () => {
                await expect(
                    this.subject.updateLeverage(
                        BigNumber.from(10).pow(9),
                        true,
                        ethers.constants.MaxUint256,
                        0
                    )
                ).to.emit(this.subject, "UpdatedLeverage");
            });

            it("reverts with wrong deadline", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether
                await expect(
                    this.subject.updateLeverage(
                        BigNumber.from(10).pow(9),
                        true,
                        1,
                        0
                    )
                ).to.be.reverted;
            });

            it("leverage is updated proportionally", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether
                const fourLeveragePositionSize =
                    await this.subject.getPositionSize();

                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(2),
                    true,
                    ethers.constants.MaxUint256,
                    0
                );
                const twoLeveragePositionSize =
                    await this.subject.getPositionSize();

                await this.subject.updateLeverage(
                    BigNumber.from(10).pow(9).mul(3),
                    false,
                    ethers.constants.MaxUint256,
                    0
                );
                const threeLeverageShortPositionSize =
                    await this.subject.getPositionSize();

                const isAClose = await this.isClose(
                    fourLeveragePositionSize.mul(2),
                    twoLeveragePositionSize.mul(4),
                    BigNumber.from(50)
                );
                const isBClose = await this.isClose(
                    threeLeverageShortPositionSize.mul(4).mul(-1),
                    fourLeveragePositionSize.mul(3),
                    BigNumber.from(50)
                );

                expect(isAClose).to.be.true;
                expect(isBClose).to.be.true;
            });

            it("access control", async () => {
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .updateLeverage(
                                    BigNumber.from(10).pow(9).mul(5),
                                    true,
                                    ethers.constants.MaxUint256,
                                    0
                                )
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#closePosition", () => {
            // several cases are tested earlier

            it("emits ClosedPosition event", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether
                await expect(
                    this.subject.closePosition(ethers.constants.MaxUint256, 0)
                ).to.emit(this.subject, "ClosedPosition");
            });

            it("reverts with wrong deadline", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether
                await expect(this.subject.closePosition(1, 0)).to.be.reverted;
            });

            it("goes to zero position", async () => {
                await this.pushIntoVault(BigNumber.from(10).pow(6).mul(4)); // longing ether
                await this.subject.closePosition(
                    ethers.constants.MaxUint256,
                    0
                );
                const positionSize = await this.subject.getPositionSize();
                expect(positionSize).to.be.eq(0);
            });

            it("access control", async () => {
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .closePosition(ethers.constants.MaxUint256, 0)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        describe("#adjustPosition", () => {
            // several cases are tested earlier

            it("emits AdjustedPosition event", async () => {
                await expect(
                    this.subject.adjustPosition(ethers.constants.MaxUint256, 0)
                ).to.emit(this.subject, "AdjustedPosition");
            });

            it("access control", async () => {
                it("not allowed: any address", async () => {
                    await withSigner(randomAddress(), async (signer) => {
                        await expect(
                            this.subject
                                .connect(signer)
                                .adjustPosition(ethers.constants.MaxUint256, 0)
                        ).to.be.revertedWith(Exceptions.FORBIDDEN);
                    });
                });
            });
        });

        integrationVaultBehavior.call(this, {});
    }
);

// TO DO: ADD TESTS WHEN THE PRICE SHIFTS (I.E TIMESTAMP MOVES; DIDN'T SUCCEED IN HOW TO DO THAT YET)
// TO DO: FIX INTEGRATION FAILED TESTS
