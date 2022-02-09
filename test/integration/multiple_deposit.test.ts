import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, randomAddress, sleep } from "../library/Helpers";
import { contract } from "../library/setup";
import { pit, RUNS } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { integer } from "fast-check";
import { ERC20RootVaultGovernance } from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { assert } from "console";
import { randomInt } from "crypto";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    erc20RootVaultNft: number;
    usdcDeployerSupply: BigNumber;
    wethDeployerSupply: BigNumber;
    strategyTreasury: Address;
    strategyPerformanceTreasury: Address;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__erc20_yearn",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let erc20VaultNft = startNft;
                    let yearnVaultNft = startNft + 1;
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    await combineVaults(
                        hre,
                        yearnVaultNft + 1,
                        [erc20VaultNft, yearnVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );
                    const yearnVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        yearnVaultNft
                    );

                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        yearnVaultNft + 1
                    );

                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );
                    this.erc20Vault = (await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    )) as ERC20Vault;
                    this.yearnVault = (await ethers.getContractAt(
                        "YearnVault",
                        yearnVault
                    )) as YearnVault;

                    // add depositor
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    this.wethDeployerSupply = BigNumber.from(10).pow(20).mul(5);
                    this.usdcDeployerSupply = BigNumber.from(10).pow(20).mul(5);

                    await mint(
                        "USDC",
                        this.deployer.address,
                        this.usdcDeployerSupply
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        this.wethDeployerSupply
                    );

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                        await ethers.getContract("ERC20RootVaultGovernance");
                    this.erc20RootVaultNft = yearnVaultNft + 1;

                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();

                    await erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                            strategyTreasury: this.strategyTreasury,
                            strategyPerformanceTreasury:
                                this.strategyPerformanceTreasury,
                            privateVault: true,
                            managementFee: 0,
                            performanceFee: 0,
                        });
                    await sleep(this.governanceDelay);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.erc20RootVaultNft);
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        pit(
            `
            when fees are zero, sum of deposit[i] = sum of withdraw[j]
        `,
            { numRuns: RUNS.mid, endOnFailure: true },
            integer({ min: 1, max: 10 }),
            integer({ min: 1, max: 10 }),
            integer({ min: 100_000, max: 1_000_000 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            integer({ min: 10 ** 11, max: 10 ** 15 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            async (
                numDeposits: number,
                numWithdraws: number,
                amountUSDC: BigNumber,
                amountWETH: BigNumber
            ) => {
                let lpAmounts: BigNumber[] = [];
                assert(
                    (await this.subject.balanceOf(this.deployer.address)).eq(
                        BigNumber.from(0)
                    )
                );
                for (var i = 0; i < numDeposits; ++i) {
                    await this.subject
                        .connect(this.deployer)
                        .deposit(
                            [
                                BigNumber.from(amountUSDC).div(numDeposits),
                                BigNumber.from(amountWETH).div(numDeposits),
                            ],
                            0
                        );
                    lpAmounts.push(
                        await this.subject.balanceOf(this.deployer.address)
                    );
                }

                for (var i = 1; i < numDeposits; ++i) {
                    expect(lpAmounts[i].sub(lpAmounts[i - 1])).to.be.equal(
                        lpAmounts[0]
                    );
                }

                const lpTokensAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                expect(lpTokensAmount).to.not.deep.equals(BigNumber.from(0));

                let erc20_tvl = await this.erc20Vault.tvl();
                let yearn_tvl = await this.yearnVault.tvl();
                let root_tvl = await this.subject.tvl();

                expect(erc20_tvl[0][0].add(yearn_tvl[0][0])).to.deep.equals(
                    root_tvl[0][0]
                );
                expect(erc20_tvl[0][1].add(yearn_tvl[0][1])).to.deep.equals(
                    root_tvl[0][1]
                );

                for (var i = 0; i < numWithdraws; ++i) {
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).div(numWithdraws),
                        [0, 0]
                    );
                }

                if (
                    !BigNumber.from(lpTokensAmount)
                        .mod(numWithdraws)
                        .eq(BigNumber.from(0))
                ) {
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).mod(numWithdraws),
                        [0, 0]
                    );
                }

                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from(0));

                expect(
                    await this.weth.balanceOf(this.deployer.address)
                ).to.be.equal(this.wethDeployerSupply);

                expect(
                    await this.usdc.balanceOf(this.deployer.address)
                ).to.be.equal(this.usdcDeployerSupply);

                return true;
            }
        );

        const setFeesFixture = deployments.createFixture(async () => {
            await this.deploymentFixture();
            let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                await ethers.getContract("ERC20RootVaultGovernance");

            await erc20RootVaultGovernance
                .connect(this.admin)
                .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                    strategyTreasury: this.strategyTreasury,
                    strategyPerformanceTreasury:
                        this.strategyPerformanceTreasury,
                    privateVault: true,
                    managementFee: BigNumber.from(20000000),
                    performanceFee: BigNumber.from(200000000),
                });
            await sleep(this.governanceDelay);
            await this.erc20RootVaultGovernance
                .connect(this.admin)
                .commitDelayedStrategyParams(this.erc20RootVaultNft);
        });

        pit(
            `
        when feez are not zero, sum of deposit[i] = sum of withdraw[j] + sum of fees[i]
        `,
            { numRuns: RUNS.mid, endOnFailure: true },
            integer({ min: 0, max: 86400 }),
            integer({ min: 3, max: 10 }),
            integer({ min: 3, max: 10 }),
            integer({ min: 0, max: 10 }),
            integer({ min: 0, max: 10 }),
            async (
                delay: number,
                numDeposits: number,
                numWithdraws: number,
                ratioUSDC: number,
                ratioWETH: number
            ) => {
                await setFeesFixture();
                let usdcDepositAmounts = [];
                let wethDepositAmounts = [];
                if (ratioWETH + ratioUSDC == 0) {
                    return true;
                }
                if (ratioWETH == 0) {
                    for (var i = 0; i < numDeposits; ++i) {
                        usdcDepositAmounts.push(
                            BigNumber.from(Math.round(Math.random() * 10 ** 6))
                                .mul(this.usdcDeployerSupply)
                                .div(BigNumber.from(10).pow(10))
                                .div(numDeposits)
                        );
                        wethDepositAmounts.push(0);
                    }
                } else if (ratioUSDC == 0) {
                    for (var i = 0; i < numDeposits; ++i) {
                        wethDepositAmounts.push(
                            BigNumber.from(Math.round(Math.random() * 10 ** 6))
                                .mul(this.wethDeployerSupply)
                                .div(BigNumber.from(10).pow(10))
                                .div(numDeposits)
                        );
                        usdcDepositAmounts.push(0);
                    }
                } else {
                    for (var i = 0; i < numDeposits; ++i) {
                        wethDepositAmounts.push(
                            BigNumber.from(Math.round(Math.random() * 10 ** 6))
                                .mul(this.wethDeployerSupply)
                                .div(BigNumber.from(10).pow(10))
                                .div(numDeposits)
                        );
                        usdcDepositAmounts.push(
                            wethDepositAmounts[i].mul(ratioUSDC).div(ratioWETH)
                        );
                    }
                }
                console.log("ratio ", ratioUSDC, " ", ratioWETH);
                console.log("given amounts\n");
                for (var i = 0; i < numDeposits; ++i) {
                    console.log(
                        "deposit ",
                        i,
                        " ",
                        Number(usdcDepositAmounts[i]),
                        " ",
                        Number(wethDepositAmounts[i])
                    );
                    await this.subject
                        .connect(this.deployer)
                        .deposit(
                            [usdcDepositAmounts[i], wethDepositAmounts[i]],
                            0
                        );
                }
                console.log("set deposits");
                let strategyTreasury = (
                    await this.erc20RootVaultGovernance.delayedStrategyParams(
                        this.erc20RootVaultNft
                    )
                ).strategyTreasury;
                let strategyPerformanceTreasury = (
                    await this.erc20RootVaultGovernance.delayedStrategyParams(
                        this.erc20RootVaultNft
                    )
                ).strategyPerformanceTreasury;
                let protocolTreasury =
                    await this.protocolGovernance.protocolTreasury();

                const lpTokensAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                expect(lpTokensAmount).to.not.deep.equals(BigNumber.from(0));
                if (ratioWETH != 0) {
                    expect(
                        await this.weth.balanceOf(this.deployer.address)
                    ).to.not.be.equal(this.wethDeployerSupply);
                } else {
                    expect(
                        await this.weth.balanceOf(this.deployer.address)
                    ).to.be.equal(this.wethDeployerSupply);
                }

                if (ratioUSDC != 0) {
                    expect(
                        await this.usdc.balanceOf(this.deployer.address)
                    ).to.not.be.equal(this.usdcDeployerSupply);
                } else {
                    expect(
                        await this.usdc.balanceOf(this.deployer.address)
                    ).to.be.equal(this.usdcDeployerSupply);
                }

                let erc20_tvl = await this.erc20Vault.tvl();
                let yearn_tvl = await this.yearnVault.tvl();
                let root_tvl = await this.subject.tvl();

                expect(erc20_tvl[0][0].add(yearn_tvl[0][0])).to.deep.equals(
                    root_tvl[0][0]
                );
                expect(erc20_tvl[0][1].add(yearn_tvl[0][1])).to.deep.equals(
                    root_tvl[0][1]
                );

                await sleep(delay);

                let withdrawAmounts: BigNumber[] = [];
                let withdrawSum: BigNumber = BigNumber.from(0);
                for (var i = 0; i < numWithdraws - 1; ++i) {
                    withdrawAmounts.push(
                        BigNumber.from(Math.round(Math.random() * 10 ** 6))
                            .mul(lpTokensAmount)
                            .div(numWithdraws)
                            .div(10 ** 6)
                    );
                    withdrawSum.add(withdrawAmounts[i]);
                }
                withdrawAmounts.push(lpTokensAmount.sub(withdrawSum));
                for (var i = 0; i < numWithdraws; ++i) {
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).div(numWithdraws),
                        [0, 0]
                    );
                }

                if (
                    !BigNumber.from(lpTokensAmount)
                        .mod(numWithdraws)
                        .eq(BigNumber.from(0))
                ) {
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).mod(numWithdraws),
                        [0, 0]
                    );
                }
                if ((await this.subject.balanceOf(strategyTreasury)).gt(0)) {
                    await this.subject.withdraw(
                        strategyTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                }
                if (
                    (
                        await this.subject.balanceOf(
                            strategyPerformanceTreasury
                        )
                    ).gt(0)
                ) {
                    await this.subject.withdraw(
                        strategyPerformanceTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                }
                if ((await this.subject.balanceOf(protocolTreasury)).gt(0)) {
                    await this.subject.withdraw(
                        protocolTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                }

                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from(0));
                expect(
                    (await this.weth.balanceOf(this.deployer.address))
                        .add(await this.weth.balanceOf(strategyTreasury))
                        .add(
                            await this.weth.balanceOf(
                                strategyPerformanceTreasury
                            )
                        )
                        .add(await this.weth.balanceOf(protocolTreasury))
                ).to.be.equal(this.wethDeployerSupply);
                expect(
                    (await this.usdc.balanceOf(this.deployer.address))
                        .add(await this.usdc.balanceOf(strategyTreasury))
                        .add(
                            await this.usdc.balanceOf(
                                strategyPerformanceTreasury
                            )
                        )
                        .add(await this.usdc.balanceOf(protocolTreasury))
                ).to.be.equal(this.usdcDeployerSupply);
                return true;
            }
        );
    }
);
