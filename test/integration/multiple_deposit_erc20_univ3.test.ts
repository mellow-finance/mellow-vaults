import hre, { getNamedAccounts } from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
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
    ERC20Token,
    IERC20RootVault,
    IntegrationVault,
    IUniswapV3Pool,
    MellowOracle,
    MockUniswapV3Pool,
    UniV3Vault,
    YearnVault,
} from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { randomInt } from "crypto";
import Common from "../library/Common";
import { assert } from "console";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { init, min } from "ramda";
import { IUniswapV3PoolImmutablesInterface } from "../types/IUniswapV3PoolImmutables";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { Contract } from "ethers";

enum EventType {
    DEPOSIT,
    WITHDRAW,
    PULL,
    PUSH,
}

enum VaultType {
    ROOT,
    UNIV3,
    ERC20,
    YEARN,
}

type Event = {
    subject: string;
    type: EventType;
    token: string;
    amount: BigNumber;
    from: string;
    to: string;
    signer: SignerWithAddress;
};

type VaultFeesParameters = {
    fees: BigNumber;
};

type FeesResult = {
    usdcFees: BigNumber;
    wethFees: BigNumber;
    totalFees: BigNumber;
};

class FeesWrapper {
    tokens: string[] = [];
    typeByAddress = new Map<string, VaultType>();
    events: Event[] = [];
    vaultParameters = new Map<VaultType, VaultFeesParameters>();

    constructor(
        _token: string[],
        _vaultAddresses: string[],
        _vaultTypes: VaultType[]
    ) {
        this.tokens = _token;
        for (var i = 0; i < _vaultAddresses.length; i++) {
            this.typeByAddress.set(_vaultAddresses[i], _vaultTypes[i]);
        }
    }

    addVaultParameters(type: VaultType, parameters: VaultFeesParameters) {
        this.vaultParameters.set(type, parameters);
    }

    async pull(
        subject: IntegrationVault,
        signer: SignerWithAddress,
        amounts: BigNumber[],
        to: string
    ) {
        await subject.connect(signer).pull(to, this.tokens, amounts, []);

        for (var i = 0; i < this.tokens.length; i++) {
            this.events.push({
                subject: subject.address,
                type: EventType.PULL,
                token: this.tokens[i],
                amount: amounts[i],
                from: signer.address,
                to: to,
                signer: signer,
            } as Event);
        }
    }

    async withdraw(
        subject: IERC20RootVault,
        signer: SignerWithAddress,
        to: string,
        amount: BigNumber,
        minTokenAmount: BigNumber[]
    ) {
        var opts = [];
        for (var i = 0; i < minTokenAmount.length; i++) {
            opts.push([]);
        }
        await subject
            .connect(signer)
            .withdraw(to, amount, minTokenAmount, opts);
        this.events.push({
            subject: subject.address,
            type: EventType.WITHDRAW,
            amount: amount,
            from: signer.address,
            to: to,
            signer: signer,
        } as Event);
    }

    async deposit(
        subject: IERC20RootVault,
        signer: SignerWithAddress,
        amounts: BigNumber[],
        minLpToken: BigNumber
    ) {
        await subject.connect(signer).deposit(amounts, minLpToken, []);
        for (var i = 0; i < this.tokens.length; i++) {
            this.events.push({
                subject: subject.address,
                type: EventType.DEPOSIT,
                token: this.tokens[i],
                amount: amounts[i],
                from: signer.address,
                signer: signer,
            } as Event);
        }
    }

    async getFees() {
        let usdcFees = BigNumber.from(0);
        let wethFees = BigNumber.from(0);
        let totalAmount = BigNumber.from(0);

        const increaseResultForToken = (token: string, fees: BigNumber) => {
            totalAmount = totalAmount.add(fees);
            if (token == "WETH") {
                wethFees = wethFees.add(fees);
            } else {
                usdcFees = usdcFees.add(fees);
            }
        };

        const accumulateFeesForVault = (
            type: VaultType,
            event: Event,
            parameters: VaultFeesParameters
        ) => {
            switch (type) {
                case (VaultType.ERC20, VaultType.YEARN): {
                    increaseResultForToken(
                        event.token,
                        event.amount.div(100).div(100)
                    );
                    break;
                }
                case VaultType.UNIV3: {
                    increaseResultForToken(
                        event.token,
                        event.amount.div(100).div(100)
                    );
                    break;
                }
                case VaultType.ROOT: {
                    throw "Impossible operation";
                }
            }
        };

        this.events.forEach((event) => {
            if (!this.typeByAddress.has(event.subject)) {
                throw "Cannot parse subject of event! Event:" + event;
            }
            const vaultType = this.typeByAddress.get(
                event.subject
            ) as VaultType;

            var parameters =
                this.vaultParameters.get(vaultType) ||
                ({ fees: BigNumber.from(0) } as VaultFeesParameters);
            switch (event.type) {
                case EventType.DEPOSIT:
                case EventType.WITHDRAW: {
                    if (parameters.fees.gt(0)) {
                        // TODO: handle non zeroFees
                    }
                    break;
                }
                case EventType.PULL: {
                    accumulateFeesForVault(vaultType, event, parameters);
                    break;
                }
                default: {
                    console.log("Error while parsing type!", event.type);
                    break;
                }
            }
        });

        return {
            usdcFees: usdcFees,
            wethFees: wethFees,
            totalFees: totalAmount,
        } as FeesResult;
    }
}

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
    positionManager: Contract;
};

type DeployOptions = {};

const UNIV3_FEE = BigNumber.from(500); // corresponds to 0.05% fee UniV3 pool
const YEARN_FEE = BigNumber.from(100); // corresponds to 0.01% fee Yearn pool

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
                    const { uniswapV3PositionManager } =
                        await getNamedAccounts();

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe.only("properties", () => {
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

            const checkTvls = async (withPull: boolean) => {
                const erc20Tvl = await this.erc20Vault.tvl();
                const univ3Tvl = await this.uniV3Vault.tvl();
                const yearnTvl = await this.yearnVault.tvl();
                const rootTvl = await this.subject.tvl();

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
                    if (withPull) {
                        expect(yearnTvl[0][i]).to.be.eq(yearnTvl[1][i]); // property of yearnVault
                        expect(univ3Tvl[0][i]).to.be.lt(univ3Tvl[1][i]);
                        expect(erc20Tvl[0][i]).to.be.eq(erc20Tvl[1][i]); // property of erc20Vault
                    } else {
                        for (var j = 0; j < 2; j++) {
                            expect(yearnTvl[j][i]).to.be.eq(0);
                            expect(univ3Tvl[j][i]).not.to.be.eq(0); // initial state
                            expect(erc20Tvl[j][i]).not.to.be.eq(0); // initial state
                        }
                        expect(erc20Tvl[0][i]).to.be.eq(erc20Tvl[1][i]);
                    }
                }
            };

            const getAverageTokenPrices = async () => {
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
                return averagePrice.div(pricesX96.length);
            };

            const calculateBalanceAfterPulling = async (
                priceBefore: BigNumber,
                priceAfter: BigNumber,
                startTime: number,
                endTime: number,
                tokenAmounts: BigNumber[]
            ) => {
                console.log("Price before pulling:", priceBefore.toString());
                console.log("Price after pulling:", priceAfter.toString());

                console.log("Start / finish times:", startTime, endTime);
                console.log(
                    "Token amounts: ",
                    tokenAmounts.map((x) => x.toString())
                );

                // before * amount_old == after * amount_new
                var result: BigNumber[] = [];
                for (var i = 0; i < tokenAmounts.length; i++) {
                    const oldAmount = tokenAmounts[i];
                    const newAmount = priceBefore
                        .mul(oldAmount)
                        .div(priceAfter);
                    result.push(newAmount);
                }

                return result;
            };

            const initUniV3Vault = async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: 500,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(20),
                    wethAmount: BigNumber.from(10).pow(20),
                });

                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result.tokenId
                );
            };

            const debugTvl = (
                tvl: [BigNumber[], BigNumber[]] & {
                    minTokenAmounts: BigNumber[];
                    maxTokenAmounts: BigNumber[];
                }
            ) => {
                console.log(
                    "tvl min:",
                    tvl[0].map((x) => x.toString())
                );
                console.log(
                    "tvl max:",
                    tvl[1].map((x) => x.toString())
                );
            };

            it.only("test", async () => {
                const numDeposits = 1;
                const numWithdraws = 1;
                const amountUSDC = BigNumber.from(10).pow(10);
                const amountWETH = BigNumber.from(10).pow(10);
                await setZeroFeesFixture();
                await initUniV3Vault();
                const feesWrapper = new FeesWrapper(
                    [this.usdc.address, this.weth.address],
                    [
                        this.erc20Vault.address,
                        this.uniV3Vault.address,
                        this.yearnVault.address,
                        this.subject.address,
                    ],
                    [
                        VaultType.ERC20,
                        VaultType.UNIV3,
                        VaultType.YEARN,
                        VaultType.ROOT,
                    ]
                );

                const usdcInitBalance = await this.usdc.balanceOf(
                    this.deployer.address
                );
                const wethInitBalance = await this.weth.balanceOf(
                    this.deployer.address
                );

                for (let i = 0; i < numDeposits; ++i) {
                    await feesWrapper.deposit(
                        this.subject,
                        this.deployer,
                        [
                            BigNumber.from(amountUSDC).div(numDeposits),
                            BigNumber.from(amountWETH).div(numDeposits),
                        ],
                        BigNumber.from(0)
                    );
                }

                const lpTokensAmount = await this.subject.balanceOf(
                    this.deployer.address
                );

                expect(lpTokensAmount).to.not.deep.equals(BigNumber.from(0));

                const amountForPullUsdc = amountUSDC;
                const amountForPullWeth = amountWETH;
                {
                    await checkTvls(false);

                    const erc20TvlBeforePulls = await this.erc20Vault.tvl();
                    const univ3TvlBeforePulls = await this.uniV3Vault.tvl();
                    const yearnTvlBeforePulls = await this.yearnVault.tvl();

                    await feesWrapper.pull(
                        this.erc20Vault,
                        this.deployer,
                        [amountForPullUsdc, amountForPullWeth],
                        this.uniV3Vault.address
                    );

                    // await feesWrapper.pull(
                    //     this.erc20Vault,
                    //     this.deployer,
                    //     [amountForPullUsdc, amountForPullWeth],
                    //     this.yearnVault.address
                    // );
                    await sleep(this.governanceDelay);

                    await checkTvls(true);

                    const erc20TvlAfterPulls = await this.erc20Vault.tvl();
                    const univ3TvlAfterPulls = await this.uniV3Vault.tvl();
                    const yearnTvlAfterPulls = await this.yearnVault.tvl();
                    console.log("Before states (erc20 univ3 yearn):");
                    debugTvl(erc20TvlBeforePulls);
                    debugTvl(univ3TvlBeforePulls);
                    debugTvl(yearnTvlBeforePulls);
                    console.log("After states (erc20 univ3 yearn):");
                    debugTvl(erc20TvlAfterPulls);
                    debugTvl(univ3TvlAfterPulls);
                    debugTvl(yearnTvlAfterPulls);
                }

                for (let i = 0; i < numWithdraws; ++i) {
                    await feesWrapper.withdraw(
                        this.subject,
                        this.deployer,
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).div(numWithdraws),
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                        ]
                    );
                }

                let remainingLpTokenBalance = await this.subject.balanceOf(
                    this.deployer.address
                );
                if (remainingLpTokenBalance.gt(0)) {
                    await feesWrapper.withdraw(
                        this.subject,
                        this.deployer,
                        this.deployer.address,
                        remainingLpTokenBalance,
                        [
                            BigNumber.from(0),
                            BigNumber.from(0),
                            BigNumber.from(0),
                        ]
                    );
                }

                const { usdcFees, wethFees } = await feesWrapper.getFees();

                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from(0));

                const wethBalance = await this.weth.balanceOf(
                    this.deployer.address
                );
                const usdcBalance = await this.usdc.balanceOf(
                    this.deployer.address
                );

                return true;
            });

            pit(
                `
                when fees are zero, sum of deposit[i] = sum of withdraw[j] without inernal vaults fees
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
                    const feesWrapper = new FeesWrapper(
                        [this.usdc.address, this.weth.address],
                        [
                            this.erc20Vault.address,
                            this.uniV3Vault.address,
                            this.yearnVault.address,
                            this.subject.address,
                        ],
                        [
                            VaultType.ERC20,
                            VaultType.UNIV3,
                            VaultType.YEARN,
                            VaultType.ROOT,
                        ]
                    );

                    let lpAmounts: BigNumber[] = [];
                    assert(
                        (
                            await this.subject.balanceOf(this.deployer.address)
                        ).eq(BigNumber.from(0))
                    );
                    for (let i = 0; i < numDeposits; ++i) {
                        await feesWrapper.deposit(
                            this.subject,
                            this.deployer,
                            [
                                BigNumber.from(amountUSDC).div(numDeposits),
                                BigNumber.from(amountWETH).div(numDeposits),
                            ],
                            BigNumber.from(0)
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

                    await checkTvls(false);

                    const amountUSDCForPull = amountUSDC.div(3);
                    const amountWETHForPull = amountWETH.div(3);

                    const timeBeforePulling = now();
                    const averagePricesBefore = await getAverageTokenPrices();
                    const amountTokensForPull =
                        amountUSDCForPull.add(amountWETHForPull);

                    await feesWrapper.pull(
                        this.erc20Vault,
                        this.deployer,
                        [amountUSDCForPull, amountWETHForPull],
                        this.yearnVault.address
                    );
                    await sleep(this.governanceDelay);

                    await feesWrapper.pull(
                        this.erc20Vault,
                        this.deployer,
                        [amountUSDCForPull, amountWETHForPull],
                        this.uniV3Vault.address
                    );
                    await sleep(this.governanceDelay);

                    await checkTvls(true);

                    for (let i = 0; i < numWithdraws; ++i) {
                        await feesWrapper.withdraw(
                            this.subject,
                            this.deployer,
                            this.deployer.address,
                            BigNumber.from(lpTokensAmount).div(numWithdraws),
                            [
                                BigNumber.from(0),
                                BigNumber.from(0),
                                BigNumber.from(0),
                            ]
                        );
                    }

                    let remainingLpTokenBalance = await this.subject.balanceOf(
                        this.deployer.address
                    );
                    if (remainingLpTokenBalance.gt(0)) {
                        await feesWrapper.withdraw(
                            this.subject,
                            this.deployer,
                            this.deployer.address,
                            remainingLpTokenBalance,
                            [
                                BigNumber.from(0),
                                BigNumber.from(0),
                                BigNumber.from(0),
                            ]
                        );
                    }

                    const { usdcFees, wethFees } = await feesWrapper.getFees();

                    const timeAfterPulling = now();
                    const averagePriceAfterPulling =
                        await getAverageTokenPrices();

                    expect(
                        await this.subject.balanceOf(this.deployer.address)
                    ).to.deep.equals(BigNumber.from(0));

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
                        withdrawLimit: Common.D18.mul(100),
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
                    const feesWrapper = new FeesWrapper(
                        [this.usdc.address, this.weth.address],
                        [
                            this.erc20Vault.address,
                            this.uniV3Vault.address,
                            this.yearnVault.address,
                            this.subject.address,
                        ],
                        [
                            VaultType.ERC20,
                            VaultType.UNIV3,
                            VaultType.YEARN,
                            VaultType.ROOT,
                        ]
                    );
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

                    await feesWrapper.deposit(
                        this.subject,
                        this.deployer,
                        [usdcDepositAmounts[0], wethDepositAmounts[0]],
                        BigNumber.from(0)
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
                        await feesWrapper.deposit(
                            this.subject,
                            this.deployer,
                            [usdcDepositAmounts[i], wethDepositAmounts[i]],
                            BigNumber.from(0)
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
                        minTvl <= maxTvl in case we have UniV3 vault in vault system
                        rootVaultTvls == yearnVaultTvls + erc20VaultTvls + uniV3VaultTvls
                    */

                    await checkTvls(false);

                    /*
                        --------------------- EARN PERFORMANCE FEES ---------------------------
                        get WETH and USDC balances on each vault
                        donate the same balances to vaults using transfer
                        LpTokenAmount remains constant => it`s price increases
                    */

                    var totalAmounts: BigNumber[] = [];
                    [
                        [this.weth, "WETH"],
                        [this.usdc, "USDC"],
                    ].forEach(async (pair) => {
                        var token = pair[0] as ERC20Token;
                        var name = pair[1] as string;
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
                                name,
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

                    const getAverageTokenPrices = async () => {
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
                        return averagePrice.div(pricesX96.length);
                    };

                    /*
                        --------------------- CALCULATE SOME PARAMETERS FOR PERFORMANCE FEES ---------------------------
                        get average price for USDC to WETH
                        get Tvls
                    */

                    const averagePricesBeforePull =
                        await getAverageTokenPrices();

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
                        withdrawSum = withdrawSum.add(withdrawAmounts[i]);
                    }
                    withdrawAmounts.push(
                        lpTokensAmount.mul(2).sub(withdrawSum)
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

                    for (let i = 0; i < numWithdraws; ++i) {
                        await feesWrapper.withdraw(
                            this.subject,
                            this.deployer,
                            this.deployer.address,
                            withdrawAmounts[i],
                            [
                                BigNumber.from(0),
                                BigNumber.from(0),
                                BigNumber.from(0),
                            ]
                        );
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
                            await feesWrapper.withdraw(
                                this.subject,
                                s,
                                strategyTreasury,
                                ethers.constants.MaxUint256,
                                [
                                    BigNumber.from(0),
                                    BigNumber.from(0),
                                    BigNumber.from(0),
                                ]
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
                                await feesWrapper.withdraw(
                                    this.subject,
                                    s,
                                    strategyPerformanceTreasury,
                                    ethers.constants.MaxUint256,
                                    [
                                        BigNumber.from(0),
                                        BigNumber.from(0),
                                        BigNumber.from(0),
                                    ]
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
                            await feesWrapper.withdraw(
                                this.subject,
                                s,
                                protocolTreasury,
                                ethers.constants.MaxUint256,
                                [
                                    BigNumber.from(0),
                                    BigNumber.from(0),
                                    BigNumber.from(0),
                                ]
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
                    ).to.be.eq(this.wethDeployerSupply.add(totalWethAmount));

                    expect(
                        (await this.usdc.balanceOf(this.deployer.address))
                            .add(await this.usdc.balanceOf(strategyTreasury))
                            .add(
                                await this.usdc.balanceOf(
                                    strategyPerformanceTreasury
                                )
                            )
                            .add(await this.usdc.balanceOf(protocolTreasury))
                    ).to.be.eq(this.usdcDeployerSupply.add(totalUsdcAmount));

                    return true;
                }
            );
        });
    }
);
