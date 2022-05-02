import hre, { getNamedAccounts } from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    compareAddresses,
    encodeToBytes,
    generateSingleParams,
    mint,
    mintUniV3Position_USDC_WETH,
    now,
    randomAddress,
    randomChoice,
    sleep,
    sleepTo,
    withSigner,
} from "../library/Helpers";
import { contract, TestContext } from "../library/setup";
import { pit, RUNS, uint256 } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect, assert } from "chai";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { AaveVault, ERC20RootVaultGovernance, ERC20Token, IIntegrationVault, ILendingPool, IntegrationVault, MellowOracle, UniV3Vault, Vault } from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { generateKeyPair, randomBytes, randomInt } from "crypto";
import { last, none } from "ramda";
import { runInThisContext } from "vm";


type PullAction = {
    from: IIntegrationVault;
    to: string;
    amount: BigNumber[];
};


type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    erc20RootVaultNft: number;
    usdcDeployerSupply: BigNumber;
    wethDeployerSupply: BigNumber;
    strategyTreasury: Address;
    strategyPerformanceTreasury: Address;
    mellowOracle: MellowOracle;
    targets: IntegrationVault[];
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__multiple_transactions",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    this.tokens = [this.usdc, this.weth];
                    for (let i = 1; i < this.tokens.length; i++) {
                        assert(compareAddresses(this.tokens[i - 1].address, this.tokens[i].address) < 0);
                    }
                    this.tokenAddresses = this.tokens
                        .map((t) => t.address.toLowerCase());
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    const uniV3PoolFee = 3000;

                    let erc20VaultNft = startNft;
                    let aaveVaultNft = startNft + 1;
                    let uniV3VaultNft = startNft + 2;
                    let yearnVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        aaveVaultNft,
                        "AaveVaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address, uniV3PoolFee],
                        }
                    );
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address],
                        }
                    );
                    await combineVaults(
                        hre,
                        yearnVaultNft + 1,
                        [erc20VaultNft, aaveVaultNft, uniV3VaultNft, yearnVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );
                    const aaveVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        aaveVaultNft
                    );
                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3VaultNft
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
                    this.aaveVault = (await ethers.getContractAt(
                        "AaveVault",
                        aaveVault
                    )) as AaveVault;
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

                    this.wethDeployerSupply = BigNumber.from(10).pow(18).mul(100);
                    this.usdcDeployerSupply = BigNumber.from(10).pow(18).mul(100);

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

                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();


                    const { uniswapV3PositionManager, aaveLendingPool } = await getNamedAccounts();
                    this.aaveLendingPool = (await ethers.getContractAt(
                        "ILendingPool",
                        aaveLendingPool
                    )) as ILendingPool;

                    this.aTokensAddresses = await Promise.all(this.tokens.map(async token => {
                        return (await this.aaveLendingPool.getReserveData(token.address)).aTokenAddress
                    }))

                    this.aTokens = await Promise.all(this.aTokensAddresses.map(async (aTokenAddress:string) => {
                        return (await ethers.getContractAt("ERC20Token", aTokenAddress))
                    }));
                        
                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );
                    
                    this.prepareUniV3Push = async () => {
                        const result = await mintUniV3Position_USDC_WETH({
                            fee: 3000,
                            tickLower: -887220,
                            tickUpper: 887220,
                            usdcAmount: BigNumber.from(10).pow(18).mul(30),
                            wethAmount: BigNumber.from(10).pow(18).mul(30),
                        });
                        await this.positionManager.functions[
                            "safeTransferFrom(address,address,uint256)"
                        ](
                            this.deployer.address,
                            this.uniV3Vault.address,
                            result.tokenId
                        );
                    };
                
                    this.mapVaultsToNames = {};
                    this.mapVaultsToNames[this.erc20Vault.address] = "zeroVault";
                    this.mapVaultsToNames[this.aaveVault.address] = "aaveVault";
                    this.mapVaultsToNames[this.yearnVault.address] = "yearnVault";
                    this.mapVaultsToNames[this.uniV3Vault.address] = "uniV3Vault";

                    this.erc20RootVaultNft = yearnVaultNft + 1;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        async function randomPullAction(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext): Promise<PullAction>  {
            let tvls = await Promise.all(this.targets.map(target => target.tvl()));
            let nonEmptyVaults = this.targets.filter((target, index) => {
                return ((tvls[index][0][0].gt(0)) || (tvls[index][0][1].gt(0)))
            });
            let {item:pullTarget} = randomChoice(nonEmptyVaults);
            let pullTargetIndex = this.targets.indexOf(pullTarget);
            let pullAmount = this.tokens.map((token, index) => BigNumber.from(tvls[pullTargetIndex][1][index]).mul(randomInt(1, 4)).div(3));
            let {item:pushTarget} = randomChoice(this.targets.filter((target: Vault) => target != pullTarget)); 
            return {from: pullTarget, to:pushTarget.address, amount:pullAmount};
        };


        async function fullPullAction(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, pullTarget:IntegrationVault): Promise<PullAction>  {
            let tvls = await pullTarget.tvl();
            let pullAmount = this.tokens.map((token, index) => BigNumber.from(tvls[1][index]));
            return {from: pullTarget, to:this.erc20Vault.address, amount:pullAmount};
        };

        async function doPullAction(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, action: PullAction) {
            // if (to.address == this.uniV3Vault.address) {
            //     if (this.) {
            //         first = false;
            //         await this.prepareUniV3Push();
            //     }
            //     options = encodeToBytes(
            //         ["uint256", "uint256", "uint256"],
            //         [
            //             ethers.constants.Zero,
            //             ethers.constants.Zero,
            //             ethers.constants.MaxUint256,
            //         ]
            //     )
            // }
            let options:any = [];
            if (action.to == this.aaveVault.address) {
                options = encodeToBytes(
                    ["uint256"],
                    [
                        ethers.constants.Zero
                    ]
                )
            }
            let untookAmount = action.amount;
            let currentTimestamp = // get current timestamp
            let currentStackQueue = this.stackQueues[action.from.address];
            let lastStackProfit = getStackProfit(amount, time, vaultType, token);
            while (lastStackProfit < untookAmount) {
                // delete stack
                untookAmount -= lastStackProfit;
                //refresh lastStackProfit
            }

            await withSigner(this.subject.address, async (signer) => {
                await action.from.connect(signer).pull(action.to, this.tokenAddresses, action.amount, options)
            });
        }

        async function printPullAction(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, action:PullAction) {
            process.stdout.write("Pulling ");
            process.stdout.write(action.amount[0].toString() + "," + action.amount[1].toString())
            process.stdout.write(" from ");
            process.stdout.write(this.mapVaultsToNames[action.from.address])
            process.stdout.write(" to ");
        }

        async function printVaults(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext) {
            let allCurrenciesBalancePromises = this.targets.map(async target => {
                let currentBalancesPromises = this.tokens.map(token => token.balanceOf(target.address))
                let currentBalancesResults = await Promise.all(currentBalancesPromises);
                return currentBalancesResults
            });
            let allCurrenciesBalanceResult = await Promise.all(allCurrenciesBalancePromises);
            console.log("Currencies balances:")
            for (let i = 0; i < this.targets.length; i++) {
                process.stdout.write(allCurrenciesBalanceResult[i][0].toString() + " " + allCurrenciesBalanceResult[i][1].toString() + " | ");
            }
            process.stdout.write("\n");
            console.log("MinTvls:");
            let tvlPromises = this.targets.map((target: Vault) => target.tvl());
            let tvlResults = await Promise.all(tvlPromises);
            this.targets.filter((target, index) =>  
                process.stdout.write(tvlResults[index][0] + " ")
            );
            process.stdout.write("\n");
            console.log("MaxTvls:");
            this.targets.filter((target, index) =>  
                process.stdout.write(tvlResults[index][1] + " ")
            );
            process.stdout.write("\n");

            return tvlResults;
        }

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

            it.only("zero fees", async () => {
                await setZeroFeesFixture();
                let depositAmount = [BigNumber.from(10).pow(6).mul(10), BigNumber.from(10).pow(18).mul(10)];
                
                await this.subject.connect(this.deployer).deposit(depositAmount, 0, []);
                this.targets = [this.erc20Vault, this.aaveVault, this.yearnVault];
                for (let i = 0; i < 100; i++) {
                    await printVaults.call(this);
                    let randomAction = await randomPullAction.call(this);
                    await printPullAction.call(this, randomAction);
                    console.log(this.mapVaultsToNames[randomAction.to])
                    await doPullAction.call(this, randomAction);

                }
                
                for (let i = 1; i < this.targets.length; i++) {
                    let pullAction = await fullPullAction.call(this, this.targets[i]);
                    await doPullAction.call(this, pullAction);
                }

                // withdraw, count withdrawn as deposit + aaveProfit + yarnProfit + univ3Profit 
            })

            it("testing", async () => {
                await setZeroFeesFixture();
                let depositAmount = [BigNumber.from(10).pow(6).mul(10), BigNumber.from(10).pow(18).mul(10)];
                
                await this.subject.connect(this.deployer).deposit(depositAmount, 0, []);  
                this.targets = [this.erc20Vault, this.aaveVault];
                await printVaults.call(this);

                await withSigner(this.subject.address, async (signer) => {
                    let options = encodeToBytes(
                        ["uint256"],
                        [
                            ethers.constants.Zero
                        ]
                    )
                    await this.erc20Vault.connect(signer).pull(this.aaveVault.address, this.tokenAddresses, depositAmount, options);
                });

                await printVaults.call(this)

                console.log("sleeping");
                await sleep(1);

                let tvlResults = await printVaults.call(this)

                process.stdout.write("balance of aToken:");
                await Promise.all(this.aTokens.map(async (aToken: any) => {
                    console.log("aToken " + aToken.address);
                    process.stdout.write((await aToken.balanceOf(this.aaveVault.address)).toString() + " ")
                }))
                process.stdout.write("\n");


                await withSigner(this.subject.address, async (signer) => {
                    await this.aaveVault.connect(signer).pull(this.erc20Vault.address, this.tokenAddresses, tvlResults[1][1], []);
                });

                await printVaults.call(this);

                let tvls = await this.subject.tvl();
                console.log("MIN TVLS: " + tvls[0][0].toString() + " " + tvls[0][1].toString());
                console.log("MAX TVLS: " + tvls[1][0].toString() + " " + tvls[1][1].toString());


                let optionsAave = encodeToBytes(
                    ["uint256"],
                    [
                        ethers.constants.Zero
                    ]
                )
                let optionsUniV3 = encodeToBytes(
                    ["uint256", "uint256", "uint256"],
                    [
                        ethers.constants.Zero,
                        ethers.constants.Zero,
                        ethers.constants.MaxUint256,
                    ]
                )
                
                let lpAmount = await this.subject.balanceOf(this.deployer.address);
                let actualWithdraw = await this.subject.connect(this.deployer).callStatic.withdraw(this.deployer.address, lpAmount.mul(2), [0,0], [randomBytes(4), optionsAave, optionsUniV3, randomBytes(4)]);
                await this.subject.connect(this.deployer).withdraw(this.deployer.address, lpAmount.mul(2), [0,0], [randomBytes(4), optionsAave, optionsUniV3, randomBytes(4)]); 
                console.log("Withdrawn: " + actualWithdraw[0].toString() + " " + actualWithdraw[1].toString());

                await printVaults.call(this);
                
                console.log("Balance is " + (await this.subject.balanceOf(this.deployer.address) + " MLP"));
            });
        });
    }
);
