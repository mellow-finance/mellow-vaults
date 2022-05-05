import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import {
    ERC20RootVault,
    YearnVault,
    ERC20Vault,
    MStrategy,
    ProtocolGovernance,
    UniV3Vault,
    ERC20RootVaultGovernance,
    IERC20RootVault,
    IntegrationVault,
    IVaultRegistry,
    ISwapRouter as SwapRouterInterface,
} from "../types";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";
import { pit, RUNS } from "../library/property";
import { integer } from "fast-check";
import { OracleParamsStruct, RatioParamsStruct } from "../types/MStrategy";
import Common from "../library/Common";
import { assert } from "console";
import { randomBytes, sign } from "crypto";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";

enum EventType {
    DEPOSIT,
    WITHDRAW,
    PULL,
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

const UNIV3_FEE = 3000; // corresponds to 0.05% fee in UniV3 pool
const YEARN_FEE = 100; // corresponds to 0.01% fee in Yearn pool

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
    yearnVault: YearnVault;
    uniV3Vault: UniV3Vault;
    erc20RootVault: ERC20RootVault;
    positionManager: Contract;
    protocolGovernance: ProtocolGovernance;
    usdcDeployerSupply: BigNumber;
    wethDeployerSupply: BigNumber;
    swapRouter: SwapRouterInterface;
};

type DeployOptions = {};

contract<MStrategy, DeployOptions, CustomContext>(
    "Integration__mstrategy_with_UniV3Vault",
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
                                UNIV3_FEE,
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

                    this.erc20RootVault = await ethers.getContractAt(
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

                    await this.erc20RootVault
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    const usdcForUniV3Mint = BigNumber.from(10)
                        .pow(6)
                        .mul(3000)
                        .sub(991);
                    const wethForUniV3Mint =
                        BigNumber.from("977868805654895061");

                    this.usdcDeployerSupply = BigNumber.from(10)
                        .pow(6)
                        .mul(3000);
                    this.wethDeployerSupply = BigNumber.from(10).pow(18);
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

                    const { uniswapV3PositionManager } =
                        await getNamedAccounts();

                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    const result = await mintUniV3Position_USDC_WETH({
                        fee: UNIV3_FEE,
                        tickLower: -887220,
                        tickUpper: 887220,
                        usdcAmount: usdcForUniV3Mint,
                        wethAmount: wethForUniV3Mint,
                    });

                    await this.positionManager.functions[
                        "safeTransferFrom(address,address,uint256)"
                    ](
                        this.deployer.address,
                        this.uniV3Vault.address,
                        result.tokenId
                    );

                    await this.weth.approve(
                        this.erc20RootVault.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.erc20RootVault.address,
                        ethers.constants.MaxUint256
                    );

                    this.erc20RootVaultNft = yearnVault + 1;
                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();

                    this.mellowOracle = await ethers.getContract(
                        "MellowOracle"
                    );

                    /*
                     * Deploy MStrategy
                     */
                    const { uniswapV3Router } = await getNamedAccounts();
                    const mStrategy = await (
                        await ethers.getContractFactory("MStrategy")
                    ).deploy(uniswapV3PositionManager, uniswapV3Router);
                    const params = [
                        tokens,
                        erc20Vault,
                        yearnVault,
                        UNIV3_FEE,
                        this.mStrategyAdmin.address,
                    ];
                    const address = await mStrategy.callStatic.createStrategy(
                        ...params
                    );
                    await mStrategy.createStrategy(...params);
                    this.subject = await ethers.getContractAt(
                        "MStrategy",
                        address
                    );

                    /*
                     * Configure oracles for the MStrategy
                     */
                    const oracleParams: OracleParamsStruct = {
                        oracleObservationDelta: 15,
                        maxTickDeviation: 10000,
                        maxSlippageD: Math.round(0.1 * 10 ** 9),
                    };
                    const ratioParams: RatioParamsStruct = {
                        tickMin: 198240 - 5000,
                        tickMax: 198240 + 5000,
                        erc20MoneyRatioD: Math.round(0.1 * 10 ** 9),
                        minErc20MoneyRatioDeviationD: Math.round(
                            0.01 * 10 ** 9
                        ),
                        minTickRebalanceThreshold: 0,
                        tickNeighborhood: 60,
                        tickIncrease: 180,
                    };
                    let txs = [];
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "setOracleParams",
                            [oracleParams]
                        )
                    );
                    txs.push(
                        this.subject.interface.encodeFunctionData(
                            "setRatioParams",
                            [ratioParams]
                        )
                    );
                    await this.subject
                        .connect(this.mStrategyAdmin)
                        .functions["multicall"](txs);

                    this.swapRouter = await ethers.getContractAt(
                        ISwapRouter,
                        uniswapV3Router
                    );
                    await this.usdc.approve(
                        this.swapRouter.address,
                        ethers.constants.MaxUint256
                    );
                    await this.weth.approve(
                        this.swapRouter.address,
                        ethers.constants.MaxUint256
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        const checkTvls = async (withPull: boolean) => {
            const erc20Tvl = await this.erc20Vault.tvl();
            const univ3Tvl = await this.uniV3Vault.tvl();
            const yearnTvl = await this.yearnVault.tvl();
            const rootTvl = await this.erc20RootVault.tvl();

            for (var i = 0; i < 2; i++) {
                for (var j = 0; j < 2; j++) {
                    expect(
                        erc20Tvl[i][j].add(univ3Tvl[i][j]).add(yearnTvl[i][j])
                    ).to.deep.equals(rootTvl[i][j]);
                }
            }
            for (var i = 0; i < 2; i++) {
                if (withPull) {
                    expect(yearnTvl[0][i]).to.be.eq(yearnTvl[1][i]); // property of yearnVault
                    // expect(univ3Tvl[0][i]).to.be.lt(univ3Tvl[1][i]);
                    expect(erc20Tvl[0][i]).to.be.eq(erc20Tvl[1][i]); // property of erc20Vault
                } else {
                    for (var j = 0; j < 2; j++) {
                        expect(yearnTvl[j][i]).to.be.eq(0);
                        // expect(univ3Tvl[j][i]).not.to.be.eq(0); // initial state
                        expect(erc20Tvl[j][i]).not.to.be.eq(0); // initial state
                    }
                    expect(erc20Tvl[0][i]).to.be.eq(erc20Tvl[1][i]);
                }
            }
        };

        const debugTvl = (
            tvl: [BigNumber[], BigNumber[]] & {
                minTokenAmounts: BigNumber[];
                maxTokenAmounts: BigNumber[];
            },
            name: string
        ) => {
            console.log("Tvls for:", name);
            console.log(
                "tvl min:",
                tvl[0].map((x) => x.toString())
            );
            console.log(
                "tvl max:",
                tvl[1].map((x) => x.toString())
            );
            console.log();
        };

        const debugTvls = async () => {
            const univ3Tvl = await this.uniV3Vault.tvl();
            const yearnTvl = await this.yearnVault.tvl();
            const erc20Tvl = await this.erc20Vault.tvl();
            const rootvTvl = await this.erc20RootVault.tvl();
            debugTvl(univ3Tvl, "univ3");
            debugTvl(yearnTvl, "yearn");
            debugTvl(erc20Tvl, "erc20");
            debugTvl(rootvTvl, "root");
        };

        const debugTokenBalances = async (flag: string) => {
            const wethBalance = await this.weth.balanceOf(
                this.deployer.address
            );
            const usdcBalance = await this.usdc.balanceOf(
                this.deployer.address
            );
            const userBalance = await this.erc20RootVault.balanceOf(
                this.deployer.address
            );

            console.log();
            console.log("*===*", flag, "*===*");
            console.log("WethBalance:", wethBalance.toString());
            console.log("UsdcBalance:", usdcBalance.toString());
            console.log("RootBalance:", userBalance.toString());
            console.log("*=================*");
            console.log();
        };

        const setNonZeroFeesFixture = deployments.createFixture(async () => {
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
                withdrawLimit: Common.D18.mul(100),
            };
            await this.protocolGovernance
                .connect(this.admin)
                .stageParams(params);
            await sleep(this.governanceDelay);
            await this.protocolGovernance.connect(this.admin).commitParams();
        });

        const generateRandomBignumber = (limit: BigNumber) => {
            assert(limit.gt(0), "Bignumber underflow");
            const bytes =
                "0x" + randomBytes(limit._hex.length * 2).toString("hex");
            return BigNumber.from(bytes).mod(limit);
        };

        const generateArraySplit = (
            w: BigNumber,
            n: number,
            from: BigNumber
        ) => {
            assert(n >= 0, "Zero length array");
            var result: BigNumber[] = [];
            if (w.lt(from.mul(n))) {
                throw "Weight underflow";
            }

            for (var i = 0; i < n; i++) {
                result.push(BigNumber.from(from));
                w = w.sub(from);
            }

            var splits: BigNumber[] = [BigNumber.from(0)];
            for (var i = 0; i < n - 1; i++) {
                splits.push(generateRandomBignumber(w.add(1)));
            }

            splits = splits.sort((x, y) => {
                return x.lt(y) ? -1 : 1;
            });

            var deltas: BigNumber[] = [];
            for (var i = 0; i < n - 1; i++) {
                deltas.push(splits[i + 1].sub(splits[i]));
                w = w.sub(deltas[i]);
            }
            deltas.push(w);

            for (var i = 0; i < n; i++) {
                result[i] = result[i].add(deltas[i]);
            }
            return result;
        };

        const getLpAmounts = async () => {
            const rootAmount = await this.erc20RootVault.balanceOf(
                this.deployer.address
            );
            const rootTvl = (await this.erc20RootVault.tvl())[0][1]; // min weth
            if (rootAmount.eq(0)) {
                return {
                    rootAmount: BigNumber.from(0),
                    univ3Amount: BigNumber.from(0),
                    yearnAmount: BigNumber.from(0),
                    erc20Amount: BigNumber.from(0),
                };
            }
            const erc20Tvl = (await this.erc20Vault.tvl())[0][1];
            const univ3Tvl = (await this.uniV3Vault.tvl())[0][1];
            const yearnTvl = (await this.yearnVault.tvl())[0][1];

            const erc20Amount = rootAmount.mul(erc20Tvl).div(rootTvl);
            const univ3Amount = rootAmount.mul(univ3Tvl).div(rootTvl);
            const yearnAmount = rootAmount.mul(yearnTvl).div(rootTvl);

            return {
                rootAmount: rootAmount,
                univ3Amount: univ3Amount,
                yearnAmount: yearnAmount,
                erc20Amount: erc20Amount,
            };
        };

        const getLpByValue = async (value: BigNumber) => {
            const rootAmount = await this.erc20RootVault.balanceOf(
                this.deployer.address
            );
            const rootTvl = (await this.erc20RootVault.tvl())[0][1]; // min weth
            return rootAmount.mul(value).div(rootTvl);
        };

        describe.only("properties", () => {
            it("Execute integration test", async () => {
                await setNonZeroFeesFixture();

                await debugTokenBalances("State A [init] initial state");
                await debugTvls();
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.erc20Vault.nft()
                    );
                await this.vaultRegistry
                    .connect(this.admin)
                    .adminApprove(
                        this.subject.address,
                        await this.yearnVault.nft()
                    );

                const usdcAmountForDeposit = this.usdcDeployerSupply;
                const wethAmountForDeposit = this.wethDeployerSupply;

                await this.erc20RootVault
                    .connect(this.deployer)
                    .deposit(
                        [usdcAmountForDeposit, wethAmountForDeposit],
                        0,
                        []
                    );
                await debugTokenBalances(
                    "State B [deposit] after increased liquidity"
                );
                await debugTvls();

                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.yearnVault.address,
                        [usdcAmountForDeposit, wethAmountForDeposit],
                        []
                    );

                await debugTokenBalances(
                    "State C [manualPull] after giving liqudity for YearnVault"
                );
                await debugTvls();

                await this.subject.connect(this.mStrategyAdmin).rebalance();
                await debugTokenBalances(
                    "State D [rebalance] after rebalance strategy with default params"
                );
                await debugTvls();

                // =================================================================
                const amount = BigNumber.from(10).pow(14);
                await mint("USDC", this.deployer.address, amount);
                await debugTokenBalances("State E [mint] minted tokens.");
                await debugTvls();

                // =================================================================
                await this.swapRouter.exactInputSingle({
                    tokenIn: this.usdc.address,
                    tokenOut: this.weth.address,
                    fee: UNIV3_FEE,
                    recipient: this.deployer.address,
                    deadline: ethers.constants.MaxUint256,
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0,
                });
                await debugTokenBalances(
                    "State F [swap] after swap by SwapRouter"
                );
                await debugTvls();

                // pull of dust ===============================================
                await sleep(this.governanceDelay);
                await this.subject
                    .connect(this.mStrategyAdmin)
                    .manualPull(
                        this.erc20Vault.address,
                        this.uniV3Vault.address,
                        [BigNumber.from(10).pow(8), BigNumber.from(10).pow(8)],
                        []
                    );

                await debugTokenBalances(
                    "State G [manualPull] after pulling small amount from erc20 to univ3"
                );
                await debugTvls();

                // =================================================================

                await this.subject.connect(this.mStrategyAdmin).rebalance();
                await debugTokenBalances(
                    "State H [rebalance] after rebalance strategy with new price params"
                );
                await debugTvls();

                return true;
            });
        });
    }
);
