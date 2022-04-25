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
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect } from "chai";
import { integer, float } from "fast-check";
import {
    ERC20RootVaultGovernance,
    MellowOracle,
    UniV3Vault,
    YearnVault,
} from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { randomInt } from "crypto";
import Common from "../library/Common";
import { assert } from "console";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
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
    "Integration__erc20_univ3",
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
                    let univ3VaultNft = startNft + 1;
                    let yearnVaultNft = startNft + 2;

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
                        univ3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                500,
                            ],
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
                        [erc20VaultNft, univ3VaultNft, yearnVaultNft],
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
                        univ3VaultNft
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
                    this.uniV3Vault = (await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    )) as UniV3Vault;

                    this.yearnVault = (await ethers.getContractAt(
                        "YearnVault",
                        yearnVault
                    )) as YearnVault;

                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    this.wethDeployerSupply = BigNumber.from(10).pow(10).mul(5);
                    this.usdcDeployerSupply = BigNumber.from(10).pow(10).mul(5);

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

                    this.erc20RootVaultNft = yearnVault + 1;
                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();

                    this.mellowOracle = await ethers.getContract(
                        "MellowOracle"
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("properties", () => {
            const setZeroFeesFixture = deployments.createFixture(async () => {
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
                        managementFee: 0,
                        performanceFee: 0,
                        depositCallbackAddress: ethers.constants.AddressZero,
                        withdrawCallbackAddress: ethers.constants.AddressZero,
                    });
                await sleep(this.governanceDelay);
                await this.erc20RootVaultGovernance
                    .connect(this.admin)
                    .commitDelayedStrategyParams(this.erc20RootVaultNft);

                const { protocolTreasury } = await getNamedAccounts();

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
            });

            pit(
                `
                when fees are zero, sum of deposit[i] = sum of withdraw[j]
            `,
                { numRuns: RUNS.mid, endOnFailure: true },
                integer({ min: 1, max: 10 }),
                integer({ min: 1, max: 10 }),
                integer({ min: 10 ** 6, max: 10 ** 9 }).map((x) =>
                    BigNumber.from(x.toString())
                ),
                integer({ min: 10 ** 7, max: 10 ** 10 }).map((x) =>
                    BigNumber.from(x.toString())
                ),
                async (
                    numDeposits: number,
                    numWithdraws: number,
                    amountUSDC: BigNumber,
                    amountWETH: BigNumber
                ) => {
                    await setZeroFeesFixture();
                    let lpAmounts: BigNumber[] = [];
                    assert(
                        (
                            await this.subject.balanceOf(this.deployer.address)
                        ).eq(BigNumber.from(0))
                    );
                    for (let i = 0; i < numDeposits; ++i) {
                        await this.subject
                            .connect(this.deployer)
                            .deposit(
                                [
                                    BigNumber.from(amountUSDC).div(numDeposits),
                                    BigNumber.from(amountWETH).div(numDeposits),
                                ],
                                0,
                                []
                            );
                        lpAmounts.push(
                            await this.subject.balanceOf(this.deployer.address)
                        );
                    }

                    for (let i = 1; i < numDeposits; ++i) {
                        expect(lpAmounts[i].sub(lpAmounts[i - 1])).to.be.equal(
                            lpAmounts[0]
                        );
                    }

                    const lpTokensAmount = await this.subject.balanceOf(
                        this.deployer.address
                    );
                    expect(lpTokensAmount).to.not.deep.equals(
                        BigNumber.from(0)
                    );

                    let erc20Tvl = await this.erc20Vault.tvl();
                    let univ3Tvl = await this.uniV3Vault.tvl();
                    let yearnTvl = await this.yearnVault.tvl();
                    let rootTvl = await this.subject.tvl();

                    for (var i = 0; i < 2; i++) {
                        for (var j = 0; j < 2; j++) {
                            expect(
                                erc20Tvl[i][j]
                                    .add(univ3Tvl[i][j])
                                    .add(yearnTvl[i][j])
                            ).to.deep.equals(rootTvl[i][j]);
                        }
                    }

                    for (var i = 0; i < 2; i++) {
                        expect(yearnTvl[0][i]).to.be.eq(yearnTvl[1][i]);
                        expect(univ3Tvl[0][i]).to.be.lte(univ3Tvl[1][i]);
                        expect(erc20Tvl[0][i]).to.be.lte(erc20Tvl[1][i]);
                    }

                    for (let i = 0; i < numWithdraws; ++i) {
                        await this.subject.withdraw(
                            this.deployer.address,
                            BigNumber.from(lpTokensAmount).div(numWithdraws),
                            [0, 0, 0],
                            [[], [], []]
                        );
                    }

                    let remainingLpTokenBalance = await this.subject.balanceOf(
                        this.deployer.address
                    );
                    assert(remainingLpTokenBalance.lt(numWithdraws ** 2));
                    if (remainingLpTokenBalance.gt(0)) {
                        await this.subject.withdraw(
                            this.deployer.address,
                            remainingLpTokenBalance,
                            [0, 0, 0],
                            [[], [], []]
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
                    ).to.be.equal(this.usdcDeployerSupply.toNumber());
                    return true;
                }
            );

            const setNonZeroFeesFixture = deployments.createFixture(
                async () => {
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
                            depositCallbackAddress:
                                ethers.constants.AddressZero,
                            withdrawCallbackAddress:
                                ethers.constants.AddressZero,
                        });
                    await sleep(this.governanceDelay);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.erc20RootVaultNft);

                    const { protocolTreasury } = await getNamedAccounts();

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
                }
            );

            const calculateExpectedPerformanceFees = (
                baseSupply: BigNumber,
                tvlToken0: BigNumber,
                lpPriceHighWaterMarkD18: BigNumber,
                performanceFee: BigNumber
            ) => {
                let lpPriceD18 = tvlToken0.mul(Common.D18).div(baseSupply);
                let toMint = BigNumber.from(0);
                if (lpPriceHighWaterMarkD18.gt(0)) {
                    toMint = baseSupply
                        .mul(lpPriceD18.sub(lpPriceHighWaterMarkD18))
                        .div(lpPriceHighWaterMarkD18)
                        .mul(performanceFee)
                        .div(Common.DENOMINATOR);
                }
                return toMint;
            };

            pit(
                `
            when fees are not zero, sum of deposit[i] = sum of withdraw[j] + sum of fees[i]
            `,
                { numRuns: RUNS.mid, endOnFailure: true },
                integer({ min: 0, max: 5 * 86400 }),
                integer({ min: 2, max: 10 }),
                integer({ min: 2, max: 10 }),
                float({ min: 0.01, max: 0.99 }),
                async (
                    delay: number,
                    numDeposits: number,
                    numWithdraws: number,
                    tokensDepositRatio: number
                ) => {
                    await setNonZeroFeesFixture();

                    let roundedTokensDepositRatio = BigNumber.from(
                        Math.round(tokensDepositRatio * 10 ** 3)
                    );

                    let usdcDepositAmounts: BigNumber[] = [];
                    let wethDepositAmounts: BigNumber[] = [];

                    let usdcDepositedAmount = BigNumber.from(0);
                    let wethDepositedAmount = BigNumber.from(0);

                    /* 
                        --------------------- SET DEPOSIT AMOUNTS ---------------------------
                        R -> ratio
                        U -> usdcDepositAmounts[i]
                        W -> wethDepositAmounts[i]
                        R = U / (U + W), R in range (0, 1)
                        let W be a random value, than
                        R * U + R * W = U
                        U * (1 - R) = W * R
                        U = W * (R / (1 - R))
                    */

                    for (let i = 0; i < numDeposits; ++i) {
                        if (i == 0) {
                            if (
                                roundedTokensDepositRatio
                                    .div(
                                        BigNumber.from(10)
                                            .pow(3)
                                            .sub(roundedTokensDepositRatio)
                                    )
                                    .gt(1)
                            ) {
                                let wethNextDepositAmount = BigNumber.from(
                                    BigNumber.from(
                                        randomInt(
                                            Number(
                                                (
                                                    await this.subject.FIRST_DEPOSIT_LIMIT()
                                                ).add(10 ** 4)
                                            ),
                                            Number(
                                                this.wethDeployerSupply
                                                    .div(10 ** 4)
                                                    .div(numDeposits)
                                            )
                                        )
                                    )
                                );
                                let usdcNextDepositAmount =
                                    wethNextDepositAmount
                                        .mul(roundedTokensDepositRatio)
                                        .div(
                                            BigNumber.from(10)
                                                .pow(3)
                                                .sub(roundedTokensDepositRatio)
                                        );

                                usdcDepositAmounts.push(usdcNextDepositAmount);
                                wethDepositAmounts.push(wethNextDepositAmount);
                            } else {
                                let usdcNextDepositAmount = BigNumber.from(
                                    BigNumber.from(
                                        randomInt(
                                            Number(
                                                (
                                                    await this.subject.FIRST_DEPOSIT_LIMIT()
                                                ).add(10 ** 4)
                                            ),
                                            Number(
                                                this.usdcDeployerSupply
                                                    .div(10 ** 4)
                                                    .div(numDeposits)
                                            )
                                        )
                                    )
                                );
                                let wethNextDepositAmount =
                                    usdcNextDepositAmount
                                        .mul(
                                            BigNumber.from(10)
                                                .pow(3)
                                                .sub(roundedTokensDepositRatio)
                                        )
                                        .div(roundedTokensDepositRatio);

                                usdcDepositAmounts.push(usdcNextDepositAmount);
                                wethDepositAmounts.push(wethNextDepositAmount);
                            }
                        } else {
                            wethDepositAmounts.push(
                                BigNumber.from(
                                    randomInt(
                                        1,
                                        Number(
                                            this.wethDeployerSupply
                                                .div(10 ** 4)
                                                .div(numDeposits)
                                        )
                                    )
                                )
                            );
                            usdcDepositAmounts.push(
                                wethDepositAmounts[i]
                                    .mul(roundedTokensDepositRatio)
                                    .div(
                                        BigNumber.from(10)
                                            .pow(3)
                                            .sub(roundedTokensDepositRatio)
                                    )
                            );
                        }

                        usdcDepositedAmount = usdcDepositedAmount.add(
                            usdcDepositAmounts[i]
                        );
                        wethDepositedAmount = wethDepositedAmount.add(
                            wethDepositAmounts[i]
                        );
                    }

                    /* 
                        --------------------- MAKE DEPOSITS ---------------------------
                        deposit U and W numDeposit times
                        set lpPriceHighWaterMarkD18
                        get lpToken balance after first deposit
                    */

                    let currentTimestamp = now() + 10 ** 6;
                    await sleepTo(currentTimestamp);
                    await this.subject
                        .connect(this.deployer)
                        .deposit(
                            [usdcDepositAmounts[0], wethDepositAmounts[0]],
                            0,
                            []
                        );
                    const lpTokenAmountAfterFirstDeposit =
                        await this.subject.balanceOf(this.deployer.address);

                    let lpPriceHighWaterMarkD18 = BigNumber.from(
                        usdcDepositAmounts[0]
                    )
                        .mul(Common.D18)
                        .div(lpTokenAmountAfterFirstDeposit);

                    if (delay > 86400) {
                        await sleepTo(currentTimestamp + delay);
                    } else {
                        await sleep(delay);
                    }

                    for (let i = 1; i < numDeposits; ++i) {
                        await this.subject
                            .connect(this.deployer)
                            .deposit(
                                [usdcDepositAmounts[i], wethDepositAmounts[i]],
                                0,
                                []
                            );
                    }

                    /* 
                        --------------------- CHECK THAT SMTH HAS BEEN DEPOSITED TO VAULTS --------
                    */

                    const {
                        strategyTreasury: strategyTreasury,
                        strategyPerformanceTreasury:
                            strategyPerformanceTreasury,
                    } = await this.erc20RootVaultGovernance.delayedStrategyParams(
                        this.erc20RootVaultNft
                    );
                    let protocolTreasury =
                        await this.protocolGovernance.protocolTreasury();

                    const lpTokensAmount = await this.subject.balanceOf(
                        this.deployer.address
                    );

                    // make sure that we aquired some lpTokens
                    expect(lpTokensAmount).to.not.deep.equals(
                        BigNumber.from(0)
                    );

                    /*
                        in case deposit amounts are greater than 0
                        usdc balance must be different
                        weth balance must be different
                    */

                    if (wethDepositedAmount.gt(0)) {
                        expect(
                            await this.weth.balanceOf(this.deployer.address)
                        ).to.not.be.equal(this.wethDeployerSupply);
                    }

                    if (usdcDepositedAmount.gt(0)) {
                        expect(
                            await this.usdc.balanceOf(this.deployer.address)
                        ).to.not.be.equal(this.usdcDeployerSupply);
                    }

                    /* 
                        --------------------- CHECK TVLS ---------------------------
                        minTvl == maxTvl in case we do not have UniV3 vault in vault system
                        rootVaultTvls == yearnVaultTvls + erc20VaultTvls + uniV3VaultTvls
                    */

                    let erc20Tvl = await this.erc20Vault.tvl();
                    let univ3Tvl = await this.uniV3Vault.tvl();
                    let yearnTvl = await this.yearnVault.tvl();
                    let rootTvl = await this.subject.tvl();

                    for (var i = 0; i < 2; i++) {
                        for (var j = 0; j < 2; j++) {
                            expect(
                                erc20Tvl[i][j]
                                    .add(yearnTvl[i][j])
                                    .add(univ3Tvl[i][j])
                            ).to.deep.equals(rootTvl[i][j]);
                        }
                    }

                    /* 
                        --------------------- EARN PERFORMANCE FEES ---------------------------
                        get WETH and USDC balances on each vault
                        donate the same balances to vaults using transfer
                        LpTokenAmount remains constant => it`s price increases
                    */

                    var totalAmounts: BigNumber[] = [];
                    [this.weth, this.usdc].forEach(async (token) => {
                        var totalAmount = BigNumber.from(0);
                        const vaults = [
                            this.erc20Vault.address,
                            this.uniV3Vault.address,
                            this.yearnVault.address,
                        ];
                        vaults.forEach(async (vault) => {
                            const currentAmout = await token.balanceOf(vault);
                            totalAmount = totalAmount.add(currentAmout);
                        });

                        if (totalAmount.gt(0)) {
                            await mint(
                                await token.name(),
                                this.deployer.address,
                                totalAmount
                            );
                        }
                        vaults.forEach(async (vault) => {
                            const currentAmout = await token.balanceOf(vault);
                            await token
                                .connect(this.deployer)
                                .transfer(vault, currentAmout);
                        });
                        totalAmounts.push(totalAmount);
                    });

                    const totalWethAmount = totalAmounts[0];
                    const totalUsdcAmount = totalAmounts[1];

                    /* 
                        --------------------- CALCULATE SOME PARAMETERS FOR PERFORMANCE FEES ---------------------------
                        get average price for USDC to WETH
                        get Tvls
                    */

                    let pricesResult = await this.mellowOracle.price(
                        this.usdc.address,
                        this.weth.address,
                        0x28
                    );
                    let pricesX96 = pricesResult.pricesX96;
                    let averagePrice = BigNumber.from(0);
                    for (let i = 0; i < pricesX96.length; ++i) {
                        averagePrice = averagePrice.add(pricesX96[i]);
                    }
                    averagePrice = averagePrice.div(pricesX96.length);

                    let tvls = await this.subject.tvl();
                    let minTvl = tvls[0];

                    /* 
                        --------------------- SET RANDOMISED WITHDRAW AMOUNTS ---------------------------
                        set randomised withdrawAmounts
                    */

                    let withdrawAmounts: BigNumber[] = [];
                    let withdrawSum: BigNumber = BigNumber.from(0);
                    for (let i = 0; i < numWithdraws - 1; ++i) {
                        withdrawAmounts.push(
                            BigNumber.from(Math.round(Math.random() * 10 ** 6))
                                .mul(lpTokensAmount)
                                .div(numWithdraws)
                                .div(Common.UNI_FEE_DENOMINATOR)
                        );
                        withdrawSum.add(withdrawAmounts[i]);
                    }
                    withdrawAmounts.push(lpTokensAmount.sub(withdrawSum));

                    /* 
                        --------------------- CALCULATE SOME PARAMETERS FOR MANAGEMENT FEES ---------------------------
                        get real management and performance fees
                        management fees will be earned on the first withdraw after delay
                        calculate actual token amounts using Tvls
                        calculate baseSupply = lpBalance[deployer] + managementFees + performanceFees
                        calculate baseTvls = Tvls - actualTokenAmounts
                    */

                    let managementFees = await this.subject.balanceOf(
                        this.strategyTreasury
                    );
                    let performanceFees = await this.subject.balanceOf(
                        this.strategyPerformanceTreasury
                    );

                    let tokenAmounts = [];
                    tokenAmounts.push(
                        withdrawAmounts[0]
                            .mul(minTvl[0])
                            .div(
                                lpTokensAmount
                                    .add(managementFees)
                                    .add(performanceFees)
                            )
                    );
                    tokenAmounts.push(
                        withdrawAmounts[0]
                            .mul(minTvl[1])
                            .div(
                                lpTokensAmount
                                    .add(managementFees)
                                    .add(performanceFees)
                            )
                    );

                    // get baseSupply and baseTvls
                    let baseSupply = lpTokensAmount
                        .add(managementFees)
                        .add(performanceFees)
                        .sub(withdrawAmounts[0]);
                    let baseTvls = [
                        minTvl[0].sub(tokenAmounts[0]),
                        minTvl[1].sub(tokenAmounts[1]),
                    ];

                    // calculate expected performance fees
                    let expectdPerformanceFee =
                        calculateExpectedPerformanceFees(
                            baseSupply,
                            baseTvls[0],
                            lpPriceHighWaterMarkD18,
                            BigNumber.from(200000000)
                        );

                    if (delay > 86400) {
                        await sleepTo(currentTimestamp + 2 * delay);
                    } else {
                        await sleep(delay);
                    }

                    /* 
                        --------------------- MAKE WITHDRAWS ---------------------------
                        make randomised withdraws numWithdraws times
                    */

                    await this.subject.withdraw(
                        this.deployer.address,
                        withdrawAmounts[0],
                        [0, 0, 0],
                        [[], [], []]
                    );

                    for (let i = 1; i < numWithdraws; ++i) {
                        await this.subject.withdraw(
                            this.deployer.address,
                            withdrawAmounts[i],
                            [0, 0, 0],
                            [[], [], []]
                        );
                    }

                    /* 
                        --------------------- COMPARE REAL FEES WITH EXPECTED FEES ---------------------------
                        if delay > governance.managementFeeChargeDelay 
                        assert (realFee - expectedFee) < (0.01 * 1%) * realFee
                    */

                    if (
                        BigNumber.from(delay).gt(
                            (
                                await this.erc20RootVaultGovernance.delayedProtocolParams()
                            ).managementFeeChargeDelay
                        )
                    ) {
                        let vaultGovernanceManagementFee = (
                            await this.erc20RootVaultGovernance.delayedStrategyParams(
                                this.erc20RootVaultNft
                            )
                        ).managementFee;
                        let realPerformanceFee = await this.subject.balanceOf(
                            strategyPerformanceTreasury
                        );
                        let realManagementFee = await this.subject.balanceOf(
                            strategyTreasury
                        );

                        // calculate expected management fee after second deposit
                        let expectedManagementFeeFirst =
                            vaultGovernanceManagementFee
                                .mul(delay)
                                .mul(lpTokenAmountAfterFirstDeposit)
                                .div(
                                    Common.DENOMINATOR.mul(24)
                                        .mul(3600)
                                        .mul(365)
                                );

                        // calculate expected management fee after first withdraw
                        let expectedManagementFeeSecond =
                            vaultGovernanceManagementFee
                                .mul(delay)
                                .mul(baseSupply)
                                .div(
                                    Common.DENOMINATOR.mul(24)
                                        .mul(3600)
                                        .mul(365)
                                );

                        // expected management fee = first fee + second fee
                        let expectedManagementFee =
                            expectedManagementFeeFirst.add(
                                expectedManagementFeeSecond
                            );

                        let managementFeeAbsDifference = expectedManagementFee
                            .sub(realManagementFee)
                            .abs();

                        /* 
                            MANAGEMENT FEES
                            dif <= 0.01 * 1% * fee
                            dif * 100 * 100 <= fee
                            dif * (10 ** 4) - fee <= 0
                        */

                        // TODO: fix
                        // expect(
                        //     managementFeeAbsDifference
                        //         .mul(10000)
                        //         .sub(realManagementFee)
                        //         .lte(0)
                        // ).to.be.null;

                        // // PERFORMANCE FEES
                        // expect(expectdPerformanceFee).to.be.equal(
                        //     realPerformanceFee
                        // );
                    }

                    /* 
                        --------------------- COLLECT ALL FEES ---------------------------
                        withdraw all fees as LpTokens and get USDC and WETH
                        make sure that received USDC/WETH equals expected USDC/WETH
                    */

                    // collect management fees
                    if (
                        (await this.subject.balanceOf(strategyTreasury)).gt(0)
                    ) {
                        let managementFee = await this.subject.balanceOf(
                            strategyTreasury
                        );
                        let performanceFee = await this.subject.balanceOf(
                            strategyPerformanceTreasury
                        );

                        let currentDeployerBalance =
                            await this.subject.balanceOf(this.deployer.address);
                        let totalLpSupply = Number(
                            currentDeployerBalance
                                .add(managementFee)
                                .add(performanceFee)
                        );
                        let tvls = (await this.subject.tvl())[0];

                        /*
                            tokenFee / tokenTvl = lpTokenBalance[strategyTreasury] / totalLpTokenSupply
                        */
                        // calculate expected fees

                        let usdcFee = managementFee
                            .mul(tvls[0])
                            .div(totalLpSupply);
                        let wethFee = managementFee
                            .mul(tvls[1])
                            .div(totalLpSupply);

                        // --------------------- WITHDRAW ---------------------------
                        await withSigner(strategyTreasury, async (s) => {
                            await this.subject
                                .connect(s)
                                .withdraw(
                                    strategyTreasury,
                                    ethers.constants.MaxUint256,
                                    [0, 0, 0],
                                    [[], [], []]
                                );
                        });

                        let usdcBalanceStrategyTreasury =
                            await this.usdc.balanceOf(this.strategyTreasury);
                        let wethBalanceStrategyTreasury =
                            await this.weth.balanceOf(this.strategyTreasury);

                        let usdcFeeAbsDifference = usdcFee
                            .sub(usdcBalanceStrategyTreasury)
                            .abs();
                        let wethFeeAbsDifference = wethFee
                            .sub(wethBalanceStrategyTreasury)
                            .abs();

                        expect(
                            usdcFeeAbsDifference
                                .mul(10000)
                                .sub(usdcBalanceStrategyTreasury)
                                .lte(0)
                        ).to.be.true;
                        expect(
                            wethFeeAbsDifference
                                .mul(10000)
                                .sub(wethBalanceStrategyTreasury)
                                .lte(0)
                        ).to.be.true;
                    }

                    // collect performance fees
                    if (
                        (
                            await this.subject.balanceOf(
                                strategyPerformanceTreasury
                            )
                        ).gt(0)
                    ) {
                        let performanceFee = await this.subject.balanceOf(
                            strategyPerformanceTreasury
                        );

                        let currentDeployerBalance =
                            await this.subject.balanceOf(this.deployer.address);
                        let totalLpSupply = Number(
                            currentDeployerBalance.add(performanceFee)
                        );
                        let tvls = (await this.subject.tvl())[0];

                        // --------------------- WITHDRAW ---------------------------
                        await withSigner(
                            strategyPerformanceTreasury,
                            async (s) => {
                                await this.subject
                                    .connect(s)
                                    .withdraw(
                                        strategyPerformanceTreasury,
                                        ethers.constants.MaxUint256,
                                        [0, 0, 0],
                                        [[], [], []]
                                    );
                            }
                        );

                        /*
                            tokenFee / tokenTvl = lpTokenBalance[strategyTreasury] / totalLpTokenSupply
                        */
                        // calculate expected fees

                        let usdcFee = performanceFee
                            .mul(tvls[0])
                            .div(totalLpSupply);
                        let wethFee = performanceFee
                            .mul(tvls[1])
                            .div(totalLpSupply);

                        let usdcBalanceStrategyPerformanceTreasury =
                            await this.usdc.balanceOf(
                                this.strategyPerformanceTreasury
                            );
                        let wethBalanceStrategyPerformanceTreasury =
                            await this.weth.balanceOf(
                                this.strategyPerformanceTreasury
                            );

                        let usdcFeeAbsDifference = usdcFee
                            .sub(usdcBalanceStrategyPerformanceTreasury)
                            .abs();
                        let wethFeeAbsDifference = wethFee
                            .sub(wethBalanceStrategyPerformanceTreasury)
                            .abs();

                        expect(
                            usdcFeeAbsDifference
                                .mul(10000)
                                .sub(usdcBalanceStrategyPerformanceTreasury)
                                .lte(0)
                        ).to.be.true;
                        expect(
                            wethFeeAbsDifference
                                .mul(10000)
                                .sub(wethBalanceStrategyPerformanceTreasury)
                                .lte(0)
                        ).to.be.true;
                    }

                    // collect protocol fees
                    if (
                        (await this.subject.balanceOf(protocolTreasury)).gt(0)
                    ) {
                        await withSigner(protocolTreasury, async (s) => {
                            await this.subject
                                .connect(s)
                                .withdraw(
                                    protocolTreasury,
                                    ethers.constants.MaxUint256,
                                    [0, 0, 0],
                                    [[], [], []]
                                );
                        });
                    }

                    /* 
                        --------------------- CHECK BALANCES EQUALITY ---------------------------
                        assert lpTokenBalance[deployer] == 0
                        assert usdcSupply + usdcAdditionalAmount == 
                                    usdcBalance[deployer] + 
                                    + usdcBalance[strategyTreeasury] 
                                    + usdcBalance[strategyPerformanceTreasury]
                                    + usdcBalance[protocolTreasury]
                        assert  wethSupply + wethAdditionalAmount == 
                                    wethBalance[deployer] + 
                                    + wethBalance[strategyTreeasury] 
                                    + wethBalance[strategyPerformanceTreasury]
                                    + wethBalance[protocolTreasury]
                    */

                    // expect(
                    //     await this.subject.balanceOf(this.deployer.address)
                    // ).to.deep.equals(BigNumber.from(0));

                    {
                        const leftPart = (
                            await this.weth.balanceOf(this.deployer.address)
                        )
                            .add(await this.weth.balanceOf(strategyTreasury))
                            .add(
                                await this.weth.balanceOf(
                                    strategyPerformanceTreasury
                                )
                            )
                            .add(await this.weth.balanceOf(protocolTreasury))
                            .toString();
                        const rightPart = this.wethDeployerSupply
                            .add(totalWethAmount)
                            .toString();
                        // TODO: fix that!
                        if (leftPart != rightPart) {
                            // console.log(
                            //     "Left must to be equal to right:",
                            //     leftPart,
                            //     rightPart
                            // );
                        }
                    }

                    {
                        const leftPart = (
                            await this.usdc.balanceOf(this.deployer.address)
                        )
                            .add(await this.usdc.balanceOf(strategyTreasury))
                            .add(
                                await this.usdc.balanceOf(
                                    strategyPerformanceTreasury
                                )
                            )
                            .add(await this.usdc.balanceOf(protocolTreasury))
                            .toString();
                        const rightPart = this.usdcDeployerSupply
                            .add(totalUsdcAmount)
                            .toString();
                        // TODO: fix that
                        if (leftPart != rightPart) {
                            // console.log(
                            //     "Left part (2) must to be eq to right part:",
                            //     leftPart,
                            //     rightPart
                            // );
                        }
                    }

                    return true;
                }
            );
        });
    }
);