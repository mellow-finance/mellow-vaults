import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { encodeToBytes, mint, sleep, withSigner } from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault, ERC20Vault, PerpFuturesVault } from "../types";
import { combineVaults, setupVault } from "../../deploy/0000_utils";

import { abi as IPerpInternalVault } from "../helpers/PerpVaultABI.json";
import { abi as IClearingHouse } from "../helpers/ClearingHouseABI.json";
import { pre } from "fast-check";
import { expect } from "chai";
import { uint256 } from "../library/property";
import { Address } from "hardhat-deploy/types";

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
                        return max > delta.mul(closeMeasure);
                    };

                    this.pushIntoVault = async (x: BigNumber) => {
                        await this.subject.push(
                            [this.usdc.address],
                            [x],
                            encodeToBytes(
                                ["uint256", "uint256"],
                                [ethers.constants.MaxUint256, 0]
                            )
                        );
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

                        let expected = x.mul(this.leverage).mul(999).div(1000); //minus trade fees 0.1%
                        if (isMinTvlMeant) {
                            const isSpotClose = await this.isClose(
                                expected,
                                tvl[0][0],
                                BigNumber.from(1000)
                            );
                            expect(isSpotClose).to.be.true;
                        } else {
                            const isSpotClose = await this.isClose(
                                expected,
                                tvl[1][0],
                                BigNumber.from(1000)
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
                expect(newTvl[0][0]).to.be.eq(0);
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
        });
    }
);
