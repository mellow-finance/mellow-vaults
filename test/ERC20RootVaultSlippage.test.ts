import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    sleep,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    ERC20Vault,
    IntegrationVault,
    UniV3Vault,
    MockOracle,
} from "./types";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import {
    DelayedProtocolParamsStructOutput,
    DelayedProtocolPerVaultParamsStructOutput,
    DelayedStrategyParamsStructOutput,
} from "./types/IERC20RootVaultGovernance";

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

                    let uniV3Helper = (await ethers.getContract("UniV3Helper"))
                        .address;
                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                uniV3PoolFee,
                                uniV3Helper,
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

                    this.helper = await ethers.getContract(
                        "ERC20RootVaultHelper"
                    );

                    this.pullExistentials =
                        await this.subject.pullExistentials();

                    for (let address of [
                        this.deployer.address,
                        this.uniV3Vault.address,
                        // this.erc20Vault.address,
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

                    const pullExistentials =
                        await this.subject.pullExistentials();
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);
                    await this.subject.deposit(
                        [
                            pullExistentials[0].mul(10),
                            pullExistentials[1].mul(10),
                        ],
                        BigNumber.from(0),
                        []
                    );

                    const { deploy } = deployments;
                    let oracleDeployParams = await deploy("MockOracle", {
                        from: this.deployer.address,
                        contract: "MockOracle",
                        args: [],
                        log: true,
                        autoMine: true,
                    });

                    this.mockOracle = await ethers.getContractAt(
                        "MockOracle",
                        oracleDeployParams.address
                    );

                    const protocolParams =
                        await this.erc20RootVaultGovernance.delayedProtocolParams();
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolParams({
                            ...protocolParams,
                            oracle: oracleDeployParams.address,
                        });
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolParams();

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        const getNextBlockTimestamp = async () => {
            // expected interval between blocks is 15 seconds, but we are adding some gap
            const intervalBetweenBlocks = 25;
            const lastBlockNumber = await ethers.provider.getBlockNumber();
            const { timestamp: lastBlockTimestamp } =
                await ethers.provider.getBlock(lastBlockNumber);
            return lastBlockTimestamp + intervalBetweenBlocks;
        };

        const calculateManagementFees = (
            managementFee: BigNumber,
            protocolFee: BigNumber,
            elapsed: BigNumber,
            lpSupply: BigNumber
        ) => {
            let result = BigNumber.from(0);
            const YEAR = BigNumber.from(365 * 24 * 3600);
            const DENOMINATOR = BigNumber.from(10).pow(9);
            if (managementFee.gt(0)) {
                const toMint = managementFee
                    .mul(elapsed)
                    .mul(lpSupply)
                    .div(YEAR.mul(DENOMINATOR));
                result = result.add(toMint);
            }
            if (protocolFee.gt(0)) {
                const toMint = protocolFee
                    .mul(elapsed)
                    .mul(lpSupply)
                    .div(YEAR.mul(DENOMINATOR));
                result = result.add(toMint);
            }
            return result;
        };

        const calculatePerformanceFees = async (
            erc20RootVault: ERC20RootVault,
            lpSupply: BigNumber,
            tvls: BigNumber[],
            performanceFees: BigNumber,
            tokens: string[],
            oracle: string
        ) => {
            if (performanceFees.eq(0)) {
                return BigNumber.from(0);
            }
            const helperAddress = await erc20RootVault.helper();
            const helper = await ethers.getContractAt(
                "ERC20RootVaultHelper",
                helperAddress
            );
            const tvlInToken0 = await helper.getTvlToken0(tvls, tokens, oracle);
            const D18 = BigNumber.from(10).pow(18);
            const lpPriceD18 = tvlInToken0.mul(D18).div(lpSupply);
            const hwmsD18 = await erc20RootVault.lpPriceHighWaterMarkD18();
            if (lpPriceD18.lte(hwmsD18)) {
                return BigNumber.from(0);
            }
            let result = BigNumber.from(0);
            if (hwmsD18.gt(0)) {
                let toMint = lpSupply.mul(lpPriceD18.sub(hwmsD18)).div(hwmsD18);
                const DENOMINATOR = BigNumber.from(10).pow(9);
                toMint = toMint.mul(performanceFees).div(DENOMINATOR);
                result = toMint;
            }
            return result;
        };

        const calculateFees = async (
            erc20RootVault: ERC20RootVault,
            tvls: BigNumber[],
            supply: BigNumber,
            strategyParams: DelayedStrategyParamsStructOutput,
            protocolParams: DelayedProtocolParamsStructOutput,
            protocolPerVaultParams: DelayedProtocolPerVaultParamsStructOutput
        ) => {
            const tokens = await erc20RootVault.vaultTokens();
            const pullExistentials = await erc20RootVault.pullExistentials();
            const nextBlockTimestamp = await getNextBlockTimestamp();
            const lastFeeCharge = await erc20RootVault.lastFeeCharge();
            const elapsed =
                BigNumber.from(nextBlockTimestamp).sub(lastFeeCharge);
            if (elapsed.lt(protocolParams.managementFeeChargeDelay)) {
                return BigNumber.from(0);
            }
            let needSkip = true;
            for (let i = 0; i < tvls.length; ++i) {
                if (tvls[i].gte(pullExistentials[i])) {
                    needSkip = false;
                }
            }
            if (needSkip) {
                return BigNumber.from(0);
            }
            const managementFees = calculateManagementFees(
                strategyParams.managementFee,
                protocolPerVaultParams.protocolFee,
                elapsed,
                supply
            );
            const performanceFees = await calculatePerformanceFees(
                erc20RootVault,
                supply,
                tvls,
                strategyParams.performanceFee,
                tokens,
                protocolParams.oracle
            );
            return managementFees.add(performanceFees);
        };

        const getLpAmount = (
            tvls: BigNumber[],
            amounts: BigNumber[],
            supply: BigNumber,
            pullExistentials: BigNumber[]
        ) => {
            let isLpAmountUpdated = false;
            let lpAmount = BigNumber.from(0);
            for (let i = 0; i < tvls.length; ++i) {
                if (tvls[i].lt(pullExistentials[i])) {
                    continue;
                }
                const tokenLpAmount = amounts[i].mul(supply).div(tvls[i]);
                if (tokenLpAmount.lt(lpAmount) || !isLpAmountUpdated) {
                    lpAmount = tokenLpAmount;
                    isLpAmountUpdated = true;
                }
            }
            const isSignificantTvl = isLpAmountUpdated;
            if (!isSignificantTvl) {
                for (let i = 0; i < tvls.length; ++i) {
                    if (amounts[i].gt(lpAmount)) {
                        lpAmount = amounts[i];
                    }
                }
            }
            return { isSignificantTvl, lpAmount };
        };

        const getNormalizedAmount = (
            tvl: BigNumber,
            amount: BigNumber,
            lpAmount: BigNumber,
            supply: BigNumber,
            isSignificantTvl: boolean,
            existentialsAmount: BigNumber
        ) => {
            if (!isSignificantTvl) {
                return amount;
            }
            if (tvl < existentialsAmount) {
                return BigNumber.from(0);
            }
            let res = tvl.mul(lpAmount).div(supply);
            if (res.gt(amount)) {
                res = amount;
            }
            return res;
        };

        const calculateExpectedDepositStats = async (
            tokenAmounts: BigNumber[]
        ) => {
            const erc20RootVault = this.subject;
            const erc20RootVaultNft = await erc20RootVault.nft();
            const strategyParams =
                await this.erc20RootVaultGovernance.delayedStrategyParams(
                    erc20RootVaultNft
                );
            const protocolPerVaultParams =
                await this.erc20RootVaultGovernance.delayedProtocolPerVaultParams(
                    erc20RootVaultNft
                );
            const protocolParams =
                await this.erc20RootVaultGovernance.delayedProtocolParams();
            const pullExistentials = await erc20RootVault.pullExistentials();
            let lpSupply = await erc20RootVault.totalSupply();
            if (lpSupply.eq(0)) {
                throw new Error("Supply should not be equal to zero");
            }
            const [minTvl, maxTvl] = await erc20RootVault.tvl();
            const fees = await calculateFees(
                erc20RootVault,
                minTvl,
                lpSupply,
                strategyParams,
                protocolParams,
                protocolPerVaultParams
            );
            lpSupply = lpSupply.add(fees);
            let { lpAmount: preLpAmount, isSignificantTvl } = getLpAmount(
                maxTvl,
                tokenAmounts,
                lpSupply,
                pullExistentials
            );
            let normalizedAmounts: BigNumber[] = Array();
            for (let i = 0; i < tokenAmounts.length; ++i) {
                normalizedAmounts.push(
                    getNormalizedAmount(
                        maxTvl[i],
                        tokenAmounts[i],
                        preLpAmount,
                        lpSupply,
                        isSignificantTvl,
                        pullExistentials[i]
                    )
                );
            }
            const { lpAmount } = getLpAmount(
                maxTvl,
                normalizedAmounts,
                lpSupply,
                pullExistentials
            );
            return {
                expectedLp: lpAmount,
                expectedTokenAmounts: normalizedAmounts,
            };
        };

        describe("test predictor", () => {
            describe("zero fees", () => {
                beforeEach(async () => {
                    const erc20RootVaultNft = await this.subject.nft();
                    let currentStrategyParams =
                        await this.erc20RootVaultGovernance.delayedStrategyParams(
                            erc20RootVaultNft
                        );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(erc20RootVaultNft, {
                            ...currentStrategyParams,
                            managementFee: BigNumber.from(0),
                            performanceFee: BigNumber.from(0),
                        });
                    let currentProtocolPerVaultParams =
                        await this.erc20RootVaultGovernance.delayedProtocolPerVaultParams(
                            erc20RootVaultNft
                        );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(erc20RootVaultNft, {
                            ...currentProtocolPerVaultParams,
                            protocolFee: BigNumber.from(0),
                        });
                    const currentProtocolParams =
                        await this.erc20RootVaultGovernance.delayedProtocolParams();
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolParams({
                            ...currentProtocolParams,
                            managementFeeChargeDelay: BigNumber.from(0),
                        });
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams(erc20RootVaultNft);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedStrategyParams(erc20RootVaultNft);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolParams();
                });
                it("works exactly", async () => {
                    const pullExistentials =
                        await this.subject.pullExistentials();
                    const defaultAmount = [
                        pullExistentials[0].mul(pullExistentials[0]),
                        pullExistentials[1].mul(pullExistentials[1]),
                    ];
                    for (let i = 1; i <= 101; i += 10) {
                        const balanceBefore = await this.subject.balanceOf(
                            this.deployer.address
                        );
                        const tokenAmounts = [
                            defaultAmount[0].mul(i),
                            defaultAmount[1].mul(i ** 2),
                        ];
                        const stats = await calculateExpectedDepositStats(
                            tokenAmounts
                        );
                        await this.subject.deposit(
                            tokenAmounts,
                            BigNumber.from(0),
                            []
                        );
                        const balanceAfter = await this.subject.balanceOf(
                            this.deployer.address
                        );
                        const depositedLp = balanceAfter.sub(balanceBefore);
                        expect(
                            stats.expectedLp.sub(depositedLp).toNumber()
                        ).to.be.eq(0);
                    }
                });
            });

            describe("non-zero performance fees", () => {
                beforeEach(async () => {
                    const erc20RootVaultNft = await this.subject.nft();
                    let currentStrategyParams =
                        await this.erc20RootVaultGovernance.delayedStrategyParams(
                            erc20RootVaultNft
                        );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(erc20RootVaultNft, {
                            ...currentStrategyParams,
                            managementFee: BigNumber.from(0),
                            performanceFee: BigNumber.from(10).pow(7).mul(50),
                            strategyPerformanceTreasury: randomAddress(),
                        });
                    let currentProtocolPerVaultParams =
                        await this.erc20RootVaultGovernance.delayedProtocolPerVaultParams(
                            erc20RootVaultNft
                        );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(erc20RootVaultNft, {
                            ...currentProtocolPerVaultParams,
                            protocolFee: BigNumber.from(0),
                        });
                    const currentProtocolParams =
                        await this.erc20RootVaultGovernance.delayedProtocolParams();
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolParams({
                            ...currentProtocolParams,
                            managementFeeChargeDelay: BigNumber.from(0),
                        });
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams(erc20RootVaultNft);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedStrategyParams(erc20RootVaultNft);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolParams();
                });

                it("works exactly", async () => {
                    const pullExistentials =
                        await this.subject.pullExistentials();
                    const defaultAmount = [
                        pullExistentials[0].mul(pullExistentials[0]),
                        pullExistentials[1].mul(pullExistentials[1]),
                    ];
                    await this.mockOracle.updatePrice(
                        BigNumber.from(1).shl(95)
                    );
                    for (let i = 1; i <= 101; i += 10) {
                        const tokenAmounts = [
                            defaultAmount[0].mul(i),
                            defaultAmount[1].mul(i ** 2),
                        ];
                        const stats = await calculateExpectedDepositStats(
                            tokenAmounts
                        );
                        const balanceBefore = await this.subject.balanceOf(
                            this.deployer.address
                        );
                        await this.subject.deposit(
                            tokenAmounts,
                            BigNumber.from(0),
                            []
                        );
                        const balanceAfter = await this.subject.balanceOf(
                            this.deployer.address
                        );
                        const depositedLp = balanceAfter.sub(balanceBefore);
                        expect(
                            stats.expectedLp.sub(depositedLp).toNumber()
                        ).to.be.eq(0);
                        await this.mockOracle.updatePrice(
                            BigNumber.from(1).shl(95 - ((i - 1) / 10) * 3)
                        );
                    }
                });
            });

            describe.only("non-zero management fees", () => {
                beforeEach(async () => {
                    const erc20RootVaultNft = await this.subject.nft();
                    let currentStrategyParams =
                        await this.erc20RootVaultGovernance.delayedStrategyParams(
                            erc20RootVaultNft
                        );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(erc20RootVaultNft, {
                            ...currentStrategyParams,
                            managementFee: BigNumber.from(10).pow(8),
                            performanceFee: BigNumber.from(0),
                            strategyTreasury: randomAddress(),
                        });
                    let currentProtocolPerVaultParams =
                        await this.erc20RootVaultGovernance.delayedProtocolPerVaultParams(
                            erc20RootVaultNft
                        );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolPerVaultParams(erc20RootVaultNft, {
                            ...currentProtocolPerVaultParams,
                            protocolFee: BigNumber.from(10).pow(7).mul(5),
                        });
                    const currentProtocolParams =
                        await this.erc20RootVaultGovernance.delayedProtocolParams();
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedProtocolParams({
                            ...currentProtocolParams,
                            managementFeeChargeDelay: BigNumber.from(0),
                        });
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolPerVaultParams(erc20RootVaultNft);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedStrategyParams(erc20RootVaultNft);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedProtocolParams();
                });

                it("works exactly", async () => {
                    const pullExistentials =
                        await this.subject.pullExistentials();
                    const defaultAmount = [
                        pullExistentials[0].mul(pullExistentials[0]),
                        pullExistentials[1].mul(pullExistentials[1]),
                    ];
                    for (let i = 1; i <= 101; i += 10) {
                        const tokenAmounts = [
                            defaultAmount[0].mul(i),
                            defaultAmount[1].mul(i ** 2),
                        ];
                        const stats = await calculateExpectedDepositStats(
                            tokenAmounts
                        );
                        const balanceBefore = await this.subject.balanceOf(
                            this.deployer.address
                        );
                        await ethers.provider.send(
                            "evm_setNextBlockTimestamp",
                            [await getNextBlockTimestamp()]
                        );
                        await this.subject.deposit(
                            tokenAmounts,
                            BigNumber.from(0),
                            []
                        );
                        const balanceAfter = await this.subject.balanceOf(
                            this.deployer.address
                        );
                        const depositedLp = balanceAfter.sub(balanceBefore);
                        expect(
                            stats.expectedLp.sub(depositedLp).toNumber()
                        ).to.be.eq(0);
                    }
                });
            });
        });
    }
);
