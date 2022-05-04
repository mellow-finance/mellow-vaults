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
import { AaveVault, AaveVault__factory, ERC20RootVaultGovernance, ERC20Token, IIntegrationVault, ILendingPool, IntegrationVault, IUniswapV3Pool, MellowOracle, UniV3Vault, Vault } from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { generateKeyPair, randomBytes, randomInt } from "crypto";
import { last, none } from "ramda";
import { runInThisContext } from "vm";
import { fromAscii } from "ethjs-util";


type PullAction = {
    from: IIntegrationVault;
    to: IIntegrationVault;
    amount: BigNumber[];
};

type VaultStateChange = {
    amount: BigNumber[];
    timestamp: BigNumber;
    balanceBefore: BigNumber;
    balanceAfter: BigNumber;
}

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
    aTokens: ERC20Token[];
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

                    this.erc20VaultNft = startNft;
                    this.aaveVaultNft = startNft + 1;
                    this.uniV3VaultNft = startNft + 2;
                    this.yearnVaultNft = startNft + 3;
                    await setupVault(
                        hre,
                        this.erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        this.aaveVaultNft,
                        "AaveVaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        this.uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address, uniV3PoolFee],
                        }
                    );
                    await setupVault(
                        hre,
                        this.yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [this.tokenAddresses, this.deployer.address],
                        }
                    );
                    await combineVaults(
                        hre,
                        this.yearnVaultNft + 1,
                        [this.erc20VaultNft, this.aaveVaultNft, this.uniV3VaultNft, this.yearnVaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.erc20VaultNft
                    );
                    const aaveVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.aaveVaultNft
                    );
                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.uniV3VaultNft
                    );
                    const yearnVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.yearnVaultNft
                    );
                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        this.yearnVaultNft + 1
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

                    this.yTokensAddresses = await Promise.all(this.tokens.map(async token => {
                        return (await this.yearnVaultGovernance.yTokenForToken(token.address))
                    }))

                    this.yTokens = await Promise.all(this.yTokensAddresses.map(async (yTokenAddress:string) => {
                        return (await ethers.getContractAt("ERC20Token", yTokenAddress))
                    }));
                        
                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );
                    
                    this.mapVaultsToNames = {};
                    this.mapVaultsToNames[this.erc20Vault.address] = "zeroVault";
                    this.mapVaultsToNames[this.aaveVault.address] = "aaveVault";
                    this.mapVaultsToNames[this.yearnVault.address] = "yearnVault";
                    this.mapVaultsToNames[this.uniV3Vault.address] = "uniV3Vault";

                    this.erc20RootVaultNft = this.yearnVaultNft + 1;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });


        async function printPullAction(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, action:PullAction) {
            process.stdout.write("Pulling ");
            process.stdout.write(action.amount[0].toString() + "," + action.amount[1].toString())
            process.stdout.write(" from ");
            process.stdout.write(this.mapVaultsToNames[action.from.address])
            process.stdout.write(" to ");
            process.stdout.write(this.mapVaultsToNames[action.to.address])
            process.stdout.write("\n");
        }

        async function printVaults(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext) {
            let allCurrenciesBalancePromises = this.targets.map(async target => {
                let currentBalancesPromises = this.tokens.map(token => token.balanceOf(target.address))
                let currentBalancesResults = await Promise.all(currentBalancesPromises);
                return currentBalancesResults
            });
            let allCurrenciesBalanceResult = await Promise.all(allCurrenciesBalancePromises);
            // console.log("Currencies balances:")
            // for (let i = 0; i < this.targets.length; i++) {
            //     process.stdout.write(allCurrenciesBalanceResult[i][0].toString() + " " + allCurrenciesBalanceResult[i][1].toString() + " | ");
            // }
            // process.stdout.write("\n");
            console.log("MinTvls:");
            let tvlPromises = this.targets.map((target: Vault) => target.tvl());
            let tvlResults = await Promise.all(tvlPromises);
            this.targets.filter((target, index) =>  
                process.stdout.write(tvlResults[index][0] + " | ")
            );
            process.stdout.write("\n");
            console.log("MaxTvls:");
            this.targets.filter((target, index) =>  
                process.stdout.write(tvlResults[index][1] + " | ")
            );
            process.stdout.write("\n");

            return tvlResults;
        }

        async function randomPullAction(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext): Promise<PullAction>  {
            let tvls = await Promise.all(this.targets.map(target => target.tvl()));
            let nonEmptyVaults = this.targets.filter((target, index) => {
                return ((tvls[index][0][0].gt(0)) || (tvls[index][0][1].gt(0)))
            });
            let {item:pullTarget} = randomChoice(nonEmptyVaults);
            let pullTargetIndex = this.targets.indexOf(pullTarget);
            let pullAmount = this.tokens.map((token, index) => BigNumber.from(tvls[pullTargetIndex][1][index]).mul(randomInt(1, 4)).div(3));
            let pushTarget = this.erc20Vault;
            if (pullTarget == this.erc20Vault) {
                pushTarget = randomChoice(this.targets.filter((target: Vault) => target != pullTarget)).item; 
            }
            return {from: pullTarget, to:pushTarget, amount:pullAmount};
        };


        async function fullPullAction(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, pullTarget:IntegrationVault): Promise<PullAction>  {
            let tvls = await pullTarget.tvl();
            let pullAmount = this.tokens.map((token, index) => BigNumber.from(tvls[1][index]));
            return {from:pullTarget, to:this.erc20Vault, amount:pullAmount};
        };

        async function getBalance(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, vaultAddress:string) {
            if (vaultAddress == this.aaveVault.address) {
                return Promise.all(this.aTokens.map(aToken => aToken.balanceOf(vaultAddress)));
                
            }
            return [BigNumber.from(0), BigNumber.from(0)];
        }

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
            let fromBalanceBefore = await getBalance.call(this, action.from.address);
            let toBalanceBefore = await getBalance.call(this, action.to.address);
            let currentTimestamp = (await ethers.provider.getBlock("latest")).timestamp;            
            await withSigner(this.subject.address, async (signer) => {
                await action.from.connect(signer).pull(action.to.address, this.tokenAddresses, action.amount, options)
            });
            let fromBalanceAfter = await getBalance.call(this, action.from.address);
            let toBalanceAfter = await getBalance.call(this, action.to.address);
            this.vaultChanges[action.from.address].push({amount:action.amount.map(amount => amount.mul(-1)), timestamp: currentTimestamp, balanceBefore:fromBalanceBefore, balanceAfter:fromBalanceAfter});
            this.vaultChanges[action.to.address].push({amount:action.amount, timestamp: currentTimestamp, balanceBefore:toBalanceBefore, balanceAfter:toBalanceAfter});
            
        }

        async function pullToUniV3Vault(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, sender:any, options:any) {
            for (let token of this.tokens) {
                if (
                    (await token.allowance(sender.address, this.positionManager.address)).eq(
                        BigNumber.from(0)
                    )
                ) {
                    await withSigner(sender.address, async (signer) => {
                        await token.connect(signer).approve(
                            this.positionManager.address,
                            ethers.constants.MaxUint256
                        );
                    });
                }
            }

            const mintParams = {
                token0: this.tokens[0].address,
                token1: this.tokens[1].address,
                fee: options.fee,
                tickLower: options.tickLower,
                tickUpper: options.tickUpper,
                amount0Desired: options.token0Amount,
                amount1Desired: options.token1Amount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: sender.address,
                deadline: ethers.constants.MaxUint256,
            };

            await withSigner(sender.address, async (signer) => {
                const result = await this.positionManager.connect(signer).callStatic.mint(mintParams);
                await this.positionManager.connect(signer).mint(mintParams);
                await withSigner(this.subject.address, async(root) => {
                    await this.vaultRegistry.connect(root).approve(sender.address, this.uniV3VaultNft);
                })
                await this.positionManager.connect(signer).functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    sender.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
            });
        }

        async function countProfit(this:TestContext<ERC20RootVault, DeployOptions> & CustomContext, vaultAddress:string) {
            let stateChanges = this.vaultChanges[vaultAddress];
            let profit = [];
            if ((vaultAddress == this.aaveVault.address) || (vaultAddress == this.yearnVault.address)) {
                for (let tokenIndex = 0; tokenIndex < this.tokens.length; tokenIndex++) {
                    let tokenProfit = BigNumber.from(0);
                    for (let i = 1; i < stateChanges.length; i++) {
                        tokenProfit = tokenProfit.add(stateChanges[i].balanceBefore[tokenIndex]).sub(stateChanges[i - 1].balanceAfter[tokenIndex]);
                    }
                    profit.push(tokenProfit);
                }
            }
            return profit;
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

            it("zero fees", async () => {
                await setZeroFeesFixture();
                let depositAmount = [BigNumber.from(10).pow(6).mul(10), BigNumber.from(10).pow(18).mul(10)];
                
                await this.subject.connect(this.deployer).deposit(depositAmount, 0, []);
                this.targets = [this.erc20Vault, this.aaveVault, this.yearnVault];
                this.vaultChanges = {};
                for (let x of this.targets) {
                    this.vaultChanges[x.address] = [];
                }
                for (let i = 0; i < 10; i++) {
                    await sleep(randomInt(10000));
                    await printVaults.call(this);
                    let randomAction = await randomPullAction.call(this);
                    await printPullAction.call(this, randomAction);
                    await doPullAction.call(this, randomAction);

                }
                
                for (let i = 1; i < this.targets.length; i++) {
                    let pullAction = await fullPullAction.call(this, this.targets[i]);
                    await printPullAction.call(this, pullAction);
                    await doPullAction.call(this, pullAction);
                }
                
                await printVaults.call(this);

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
                let actualWithdraw = await this.subject.connect(this.deployer).callStatic.withdraw(this.deployer.address, lpAmount, [0,0], [randomBytes(4), optionsAave, optionsUniV3, randomBytes(4)]);
                await this.subject.connect(this.deployer).withdraw(this.deployer.address, lpAmount.mul(2), [0,0], [randomBytes(4), optionsAave, optionsUniV3, randomBytes(4)]); 
                console.log("Withdrawn: " + actualWithdraw[0].toString() + " " + actualWithdraw[1].toString());

                let aaveProfit = await countProfit.call(this, this.aaveVault.address);
                console.log("Aave profit is " + aaveProfit[0].toString() + ", " + aaveProfit[1].toString());
                let yearnProfit = await countProfit.call(this, this.yearnVault.address);
                console.log("Yearn profit is " + yearnProfit[0].toString() + ", " + yearnProfit[1].toString());

                for (let tokenIndex = 0; tokenIndex < this.tokens.length; tokenIndex++) {
                    let expectedDeposit = actualWithdraw[tokenIndex].sub(aaveProfit[tokenIndex]).sub(yearnProfit[tokenIndex]);
                    expect(expectedDeposit).to.be.gt(depositAmount[tokenIndex].mul(99).div(100))
                    expect(expectedDeposit).to.be.lt(depositAmount[tokenIndex].mul(101).div(100))
                }
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

            it("testing yearn", async () => {
                await setZeroFeesFixture();
                let depositAmount = [BigNumber.from(10).pow(6).mul(10), BigNumber.from(10).pow(18).mul(10)];
                
                await this.subject.connect(this.deployer).deposit(depositAmount, 0, []);  
                this.targets = [this.erc20Vault, this.yearnVault];
                await printVaults.call(this);

                await withSigner(this.subject.address, async (signer) => {
                    let options:any[] = [];
                    await this.erc20Vault.connect(signer).pull(this.yearnVault.address, this.tokenAddresses, depositAmount, options);
                });

                await printVaults.call(this)

                console.log("sleeping");
                await sleep(1000000000);

                let tvlResults = await printVaults.call(this)

                process.stdout.write("balance of yToken:");
                await Promise.all(this.yTokens.map(async (yToken: any) => {
                    console.log("yToken " + yToken.address);
                    process.stdout.write((await yToken.balanceOf(this.yearnVault.address)).toString() + " ")
                }))
                process.stdout.write("\n");


                await withSigner(this.subject.address, async (signer) => {
                    await this.yearnVault.connect(signer).pull(this.erc20Vault.address, this.tokenAddresses, tvlResults[1][1], []);
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

            it.only("testing univ3", async () => {
                await setZeroFeesFixture();
                let depositAmount = [BigNumber.from(10).pow(6).mul(20), BigNumber.from(10).pow(18).mul(20)];
                
                await this.subject.connect(this.deployer).deposit(depositAmount, 0, []);  
                this.targets = [this.erc20Vault, this.uniV3Vault];
                await printVaults.call(this);

                await pullToUniV3Vault.call(this, this.erc20Vault, {
                    fee: 3000,
                    tickLower: -887220,
                    tickUpper: 887220,
                    token0Amount: BigNumber.from(10).pow(6).mul(10),
                    token1Amount: BigNumber.from(10).pow(18).mul(10),
                })

                let poolAddress = await this.uniswapV3Factory.getPool(
                                            this.tokens[0],
                                            this.tokens[1],
                                            3000
                                        );
                const pool: IUniswapV3Pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    poolAddress
                );
                let poolSlot0 = await pool.slot0();
                console.log("end this");
                console.log(poolSlot0.sqrtPriceX96);
                await printVaults.call(this);

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

                console.log("sleeping");
                await sleep(1000000000);

                
                let tvlResults1 = await printVaults.call(this)

                await withSigner(this.subject.address, async (signer) => {
                    await this.erc20Vault.connect(signer).pull(this.uniV3Vault.address, this.tokenAddresses, tvlResults1[0][0], optionsUniV3);
                });

                let tvlResults = await printVaults.call(this)

                await withSigner(this.subject.address, async (signer) => {
                    await this.uniV3Vault.connect(signer).pull(this.erc20Vault.address, this.tokenAddresses, tvlResults[1][1], []);
                });

                await printVaults.call(this);

                let tvls = await this.subject.tvl();
                console.log("MIN TVLS: " + tvls[0][0].toString() + " " + tvls[0][1].toString());
                console.log("MAX TVLS: " + tvls[1][0].toString() + " " + tvls[1][1].toString());
                
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
