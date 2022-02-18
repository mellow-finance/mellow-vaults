import hre, { getNamedAccounts } from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { pit, RUNS } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect } from "chai";
import { integer } from "fast-check";
import { ERC20RootVaultGovernance, MellowOracle } from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { assert } from "console";
import { randomInt } from "crypto";
import { deposit } from "../../tasks/vaults";
import { Runnable } from "mocha";
import { min } from "ramda";
import { LOADIPHLPAPI } from "dns";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    erc20RootVaultNft: number;
    usdcDeployerSupply: BigNumber;
    wethDeployerSupply: BigNumber;
    strategyTreasury: Address;
    strategyPerformanceTreasury: Address;
    mellowOracle: MellowOracle;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__erc20_yearn",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;
                    const { protocolTreasury } = await getNamedAccounts();
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

                    this.wethDeployerSupply = BigNumber.from(10).pow(18).mul(5);
                    this.usdcDeployerSupply = BigNumber.from(10).pow(18).mul(5);

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
                    const params = {
                        forceAllowMask: ALLOW_MASK,
                        maxTokensPerVault: 10,
                        governanceDelay: 86400,
                        protocolTreasury,
                        withdrawLimit: BigNumber.from(10).pow(20),
                    };
                    await this.protocolGovernance
                        .connect(this.admin)
                        .stageParams(params);
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitParams();
                    this.mellowOracle = await ethers.getContract(
                        "MellowOracle"
                    );
                    assert(
                        this.mellowOracle.address !==
                            ethers.constants.AddressZero
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        // pit(
        //     `
        //     when fees are zero, sum of deposit[i] = sum of withdraw[j]
        // `,
        //     { numRuns: RUNS.mid, endOnFailure: true },
        //     integer({ min: 1, max: 10 }),
        //     integer({ min: 1, max: 10 }),
        //     integer({ min: 100_000, max: 1_000_000 }).map((x) =>
        //         BigNumber.from(x.toString())
        //     ),
        //     integer({ min: 10 ** 11, max: 10 ** 15 }).map((x) =>
        //         BigNumber.from(x.toString())
        //     ),
        //     async (
        //         numDeposits: number,
        //         numWithdraws: number,
        //         amountUSDC: BigNumber,
        //         amountWETH: BigNumber
        //     ) => {
        //         let lpAmounts: BigNumber[] = [];
        //         assert(
        //             (await this.subject.balanceOf(this.deployer.address)).eq(
        //                 BigNumber.from(0)
        //             )
        //         );
        //         for (var i = 0; i < numDeposits; ++i) {
        //             await this.subject
        //                 .connect(this.deployer)
        //                 .deposit(
        //                     [
        //                         BigNumber.from(amountUSDC).div(numDeposits),
        //                         BigNumber.from(amountWETH).div(numDeposits),
        //                     ],
        //                     0
        //                 );
        //             lpAmounts.push(
        //                 await this.subject.balanceOf(this.deployer.address)
        //             );
        //         }

        //         for (var i = 1; i < numDeposits; ++i) {
        //             expect(lpAmounts[i].sub(lpAmounts[i - 1])).to.be.equal(
        //                 lpAmounts[0]
        //             );
        //         }

        //         const lpTokensAmount = await this.subject.balanceOf(
        //             this.deployer.address
        //         );
        //         expect(lpTokensAmount).to.not.deep.equals(BigNumber.from(0));

        //         let erc20_tvl = await this.erc20Vault.tvl();
        //         let yearn_tvl = await this.yearnVault.tvl();
        //         let root_tvl = await this.subject.tvl();

        //         expect(erc20_tvl[0][0].add(yearn_tvl[0][0])).to.deep.equals(
        //             root_tvl[0][0]
        //         );
        //         expect(erc20_tvl[0][1].add(yearn_tvl[0][1])).to.deep.equals(
        //             root_tvl[0][1]
        //         );

        //         for (var i = 0; i < numWithdraws; ++i) {
        //             await this.subject.withdraw(
        //                 this.deployer.address,
        //                 BigNumber.from(lpTokensAmount).div(numWithdraws),
        //                 [0, 0]
        //             );
        //         }

        //         if (
        //             !BigNumber.from(lpTokensAmount)
        //                 .mod(numWithdraws)
        //                 .eq(BigNumber.from(0))
        //         ) {
        //             await this.subject.withdraw(
        //                 this.deployer.address,
        //                 BigNumber.from(lpTokensAmount).mod(numWithdraws),
        //                 [0, 0]
        //             );
        //         }

        //         expect(
        //             await this.subject.balanceOf(this.deployer.address)
        //         ).to.deep.equals(BigNumber.from(0));

        //         expect(
        //             await this.weth.balanceOf(this.deployer.address)
        //         ).to.be.equal(this.wethDeployerSupply);

        //         expect(
        //             await this.usdc.balanceOf(this.deployer.address)
        //         ).to.be.equal(this.usdcDeployerSupply);

        //         return true;
        //     }
        // );

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

        const calculateExcepctedPerformanceFees = (
            baseSupply: BigNumber,
            baseTvls: BigNumber[],
            tvlToken0: BigNumber,
            lpPriceHighWaterMarkD18: BigNumber,
            performanceFee: BigNumber
        ) => {
            let denominator18 = BigNumber.from(10).pow(10);
            let lpPriceD18 = tvlToken0.mul(denominator18).div(baseSupply);
            let toMint = BigNumber.from(0);
            if (lpPriceHighWaterMarkD18.gt(0)) {
                toMint = baseSupply.mul(lpPriceD18.sub(lpPriceHighWaterMarkD18)).div(lpPriceHighWaterMarkD18);
                console.log("toMint1 ", toMint);
                toMint = toMint.mul(performanceFee).div(BigNumber.from(10).pow(9));
                console.log("toMint2 ", toMint);
            }
            return toMint;
        };

        //FIXME
        pit(
            `
        when fees are not zero, sum of deposit[i] = sum of withdraw[j] + sum of fees[i]
        `,
            { numRuns: 1, endOnFailure: true },
            integer({ min: 86401, max: 5 * 86400 }),
            integer({ min: 2, max: 10 }),
            integer({ min: 2, max: 10 }),
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
                console.log("\n\n NEXT ROUND --------------------------------");
                console.log("numDeposits ", numDeposits);
                console.log("numWithdraws ", numWithdraws);
                console.log("delay ", delay);
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
                console.log(
                    "deposit ",
                    0,
                    " ",
                    Number(usdcDepositAmounts[0]),
                    " ",
                    Number(wethDepositAmounts[0])
                );
                await this.subject
                    .connect(this.deployer)
                    .deposit([usdcDepositAmounts[0], wethDepositAmounts[0]], 0);
                const lpTokenAmountAfterFirstDeposit =
                    await this.subject.balanceOf(this.deployer.address);
                
                //FullMath.mulDiv(tvlToken0, CommonLibrary.D18, baseSupply);
                let lpPriceHighWaterMarkD18 = BigNumber.from(usdcDepositAmounts[0]).mul(BigNumber.from(10).pow(18)).div(lpTokenAmountAfterFirstDeposit);
                console.log("\ncalculated lpPriceHighWaterMarkD18 ", Number(lpPriceHighWaterMarkD18));

                await sleep(delay);

                // earn management fees
                // does not earn performance fees
                for (var i = 1; i < numDeposits; ++i) {
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

                console.log("\n\nTOTAL LP SUPPLY ", Number(lpTokensAmount));

                const wethAmountOnERC20Vault = await this.weth.balanceOf(
                    this.erc20Vault.address
                );
                const usdcAmountOnERC20Vault = await this.usdc.balanceOf(
                    this.erc20Vault.address
                );
                const wethAmountOnYearnVault = await this.weth.balanceOf(
                    this.yearnVault.address
                );
                const usdcAmountOnYearnVault = await this.usdc.balanceOf(
                    this.yearnVault.address
                );
                console.log(
                    "wethAmountOnERC20Vault ",
                    Number(wethAmountOnERC20Vault)
                );
                console.log(
                    "usdcAmountOnERC20Vault ",
                    Number(usdcAmountOnERC20Vault)
                );
                console.log(
                    "wethAmountOnYearnVault ",
                    Number(wethAmountOnYearnVault)
                );
                console.log(
                    "usdcAmountOnYearnVault ",
                    Number(usdcAmountOnYearnVault)
                );
                const additionalUsdcAmount = usdcAmountOnERC20Vault.add(
                    usdcAmountOnYearnVault
                );
                const additionalWethAmount = wethAmountOnERC20Vault.add(
                    wethAmountOnYearnVault
                );
                if (additionalUsdcAmount.gt(0)) {
                    await mint(
                        "USDC",
                        this.deployer.address,
                        additionalUsdcAmount
                    );
                }
                if (additionalWethAmount.gt(0)) {
                    await mint(
                        "WETH",
                        this.deployer.address,
                        additionalWethAmount
                    );
                }
                console.log("minted");
                await this.weth
                    .connect(this.deployer)
                    .transfer(this.erc20Vault.address, wethAmountOnERC20Vault);
                await this.usdc
                    .connect(this.deployer)
                    .transfer(this.erc20Vault.address, usdcAmountOnERC20Vault);

                await this.weth
                    .connect(this.deployer)
                    .transfer(this.yearnVault.address, wethAmountOnYearnVault);
                await this.usdc
                    .connect(this.deployer)
                    .transfer(this.yearnVault.address, usdcAmountOnYearnVault);

                console.log("\nTRANSFERED");
                console.log(
                    "weth check ",
                    Number(await this.weth.balanceOf(this.deployer.address))
                );
                console.log(
                    "usdc check ",
                    Number(await this.usdc.balanceOf(this.deployer.address))
                );
                console.log(
                    "lp check ",
                    Number(await this.subject.balanceOf(this.deployer.address))
                );

                // earn management fees on the next withdraw
                // earn performance fees
                await sleep(delay);
                console.log("\n\nTOTAL LP SUPPLY 2 ", Number(lpTokensAmount));
                console.log("weth ", this.weth.address);
                console.log("usdc ", this.usdc.address);
                let pricesResult = await this.mellowOracle.price(
                    this.usdc.address,
                    this.weth.address,
                    0x28
                );
                let pricesX96 = pricesResult.pricesX96;
                let averagePrice = BigNumber.from(0);
                for (var i = 0; i < pricesX96.length; ++i) {
                    averagePrice = averagePrice.add(pricesX96[i]);
                }
                averagePrice = averagePrice.div(pricesX96.length);
                console.log("\nAverage price ", Number(averagePrice));

                let tvls = await this.subject.tvl();
                let minTvl = tvls[0];
                let maxTvl = tvls[1];
                console.log("\nminTvl ", Number(minTvl[0]), Number(minTvl[1]));
                console.log("\nmaxTvl ", Number(maxTvl[0]), Number(maxTvl[1]));

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

                let tokenAmounts = [];
                let managementFees = await this.subject.balanceOf(
                    this.strategyTreasury
                );
                let performanceFees = await this.subject.balanceOf(
                    this.strategyPerformanceTreasury
                );
                tokenAmounts.push(
                    withdrawAmounts[0]
                        .mul(minTvl[0])
                        .div(
                            Number(
                                lpTokensAmount
                                    .add(managementFees)
                                    .add(performanceFees)
                            )
                        )
                );
                tokenAmounts.push(
                    withdrawAmounts[0]
                        .mul(minTvl[1])
                        .div(
                            Number(
                                lpTokensAmount
                                    .add(managementFees)
                                    .add(performanceFees)
                            )
                        )
                );

                console.log(
                    "TOTAL LP SUPPLY ",
                    Number(
                        lpTokensAmount.add(managementFees).add(performanceFees)
                    )
                );
                console.log("BASE SUPPLY ", lpTokensAmount.sub(withdrawAmounts[0]));
                console.log("WITHDRAWING FIRST LP AMOUNT ", Number(withdrawAmounts[0]));

                for (var i = 0; i < numWithdraws; ++i) {
                    console.log(
                        "withdraw lp amount",
                        Number(withdrawAmounts[i])
                    );
                    await this.subject.withdraw(
                        this.deployer.address,
                        withdrawAmounts[i],
                        [0, 0]
                    );
                }

                console.log("BALANCES\n");
                console.log(
                    "strategy management ",
                    Number(await this.subject.balanceOf(strategyTreasury))
                );

                console.log(
                    "strategy performance ",
                    Number(
                        await this.subject.balanceOf(
                            strategyPerformanceTreasury
                        )
                    )
                );

                console.log(
                    "protocol ",
                    Number(await this.subject.balanceOf(protocolTreasury))
                );

                if (
                    BigNumber.from(delay).gt(
                        (
                            await this.erc20RootVaultGovernance.delayedProtocolParams()
                        ).managementFeeChargeDelay
                    )
                ) {
                    let expectedManagementFee = (
                        await this.erc20RootVaultGovernance.delayedStrategyParams(
                            this.erc20RootVaultNft
                        )
                    ).managementFee
                        .mul(delay)
                        .mul(
                            lpTokensAmount
                                .sub(withdrawAmounts[0])
                                .add(lpTokenAmountAfterFirstDeposit)
                        )
                        .div(
                            BigNumber.from(10).pow(9).mul(24).mul(3600).mul(365)
                        );
                    let realManagementFee = await this.subject.balanceOf(
                        strategyTreasury
                    );

                    let managementFeeAbsDifference = expectedManagementFee
                        .sub(realManagementFee)
                        .abs();

                    console.log("real fee ", Number(realManagementFee));
                    console.log("expected fee ", Number(expectedManagementFee));
                    console.log("abs dif ", Number(managementFeeAbsDifference));
                    console.log(
                        "calculations ",
                        Number(
                            managementFeeAbsDifference
                                .mul(5000)
                                .sub(realManagementFee)
                        )
                    );

                    expect(
                        managementFeeAbsDifference
                            .mul(1000)
                            .sub(realManagementFee)
                            .lte(0)
                    ).to.be.true;
                }

                console.log("management fee passed");

                if ((await this.subject.balanceOf(strategyTreasury)).gt(0)) {
                    console.log("\nnon zero management fees");
                    await this.subject.withdraw(
                        strategyTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                    console.log("\nstrategy treasury withdraw done");
                }
                console.log("management fee collected");
                if (
                    (
                        await this.subject.balanceOf(
                            strategyPerformanceTreasury
                        )
                    ).gt(0)
                ) {
                    console.log("\nnon zero performance fees");
                    await this.subject.withdraw(
                        strategyPerformanceTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                    console.log("strategy performance treasury withdraw done");
                }
                console.log("performance fee collected");
                if ((await this.subject.balanceOf(protocolTreasury)).gt(0)) {
                    console.log("\nnon zero protocol fees");
                    await this.subject.withdraw(
                        protocolTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                    console.log("protocol treasury withdraw done");
                }
                console.log("protocol fee collected");

                console.log("collected fees and final checks");

                console.log("\nFINAL BALANCES\n");
                console.log(
                    "strategy management ",
                    Number(await this.subject.balanceOf(strategyTreasury))
                );

                console.log(
                    "strategy performance ",
                    Number(
                        await this.subject.balanceOf(
                            strategyPerformanceTreasury
                        )
                    )
                );

                console.log(
                    "protocol ",
                    Number(await this.subject.balanceOf(protocolTreasury))
                );

                console.log(
                    "deployer ",
                    Number(await this.subject.balanceOf(this.deployer.address))
                );

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
                ).to.be.equal(
                    this.wethDeployerSupply.add(additionalWethAmount)
                );
                console.log("weth correct");
                expect(
                    (await this.usdc.balanceOf(this.deployer.address))
                        .add(await this.usdc.balanceOf(strategyTreasury))
                        .add(
                            await this.usdc.balanceOf(
                                strategyPerformanceTreasury
                            )
                        )
                        .add(await this.usdc.balanceOf(protocolTreasury))
                ).to.be.equal(
                    this.usdcDeployerSupply.add(additionalUsdcAmount)
                );
                console.log("usdc correct");
                return true;
            }
        );
    }
);
