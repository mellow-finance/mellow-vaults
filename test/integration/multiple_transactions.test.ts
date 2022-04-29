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
import { contract } from "../library/setup";
import { pit, RUNS, uint256 } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect, assert } from "chai";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { AaveVault, ERC20RootVaultGovernance, ILendingPool, MellowOracle, UniV3Vault } from "../types";
import { Address } from "hardhat-deploy/dist/types";
import { generateKeyPair, randomBytes, randomInt } from "crypto";
import { none } from "ramda";

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
                    this.tokensAdresses = this.tokens
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
                            createVaultArgs: [this.tokensAdresses, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        aaveVaultNft,
                        "AaveVaultGovernance",
                        {
                            createVaultArgs: [this.tokensAdresses, this.deployer.address],
                        }
                    );
                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [this.tokensAdresses, this.deployer.address, uniV3PoolFee],
                        }
                    );
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [this.tokensAdresses, this.deployer.address],
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

                    console.log("atokenaddresses");
                    console.log(this.aTokensAddresses);

                    this.aTokens = await Promise.all(this.aTokensAddresses.map(async (aTokenAddress:string) => {
                        return (await ethers.getContractAt("ERC20Token", aTokenAddress))
                    }));

                    console.log("atokens:");
                    console.log(this.aTokens);
                        
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
                
                    this.erc20RootVaultNft = yearnVaultNft + 1;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        async function printVaults(vaults:any[], tokens:any[]) {
            let allCurrenciesBalancePromises = vaults.map(async target => {
                let currentBalancesPromises = tokens.map(token => token.balanceOf(target.address))
                let currentBalancesResults = await Promise.all(currentBalancesPromises);
                return currentBalancesResults
            });
            let allCurrenciesBalanceResult = await Promise.all(allCurrenciesBalancePromises);
            console.log("Currencies balances:")
            for (let i = 0; i < vaults.length; i++) {
                process.stdout.write(allCurrenciesBalanceResult[i][0].toString() + " " + allCurrenciesBalanceResult[i][1].toString() + " | ");
            }
            process.stdout.write("\n");
            console.log("MinTvls:");
            let tvlPromises = vaults.map(target => target.tvl());
            let tvlResults = await Promise.all(tvlPromises);
            vaults.filter((target, index) =>  
                process.stdout.write(tvlResults[index][0] + " ")
            );
            process.stdout.write("\n");
            console.log("MaxTvls:");
            vaults.filter((target, index) =>  
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

            it.only("aave amounts", async () => {
                await setZeroFeesFixture();
                let depositAmount = [BigNumber.from(10).pow(6).mul(10), BigNumber.from(10).pow(18).mul(10)];
                
                await this.subject.connect(this.deployer).deposit(depositAmount, 0, []);  
                
                await printVaults([this.erc20Vault, this.aaveVault], this.tokens);

                await withSigner(this.subject.address, async (signer) => {
                    let options = encodeToBytes(
                        ["uint256"],
                        [
                            ethers.constants.Zero
                        ]
                    )
                    await this.erc20Vault.connect(signer).pull(this.aaveVault.address, this.tokensAdresses, depositAmount, options);
                });

                await printVaults([this.erc20Vault, this.aaveVault], this.tokens);

                console.log("sleeping");
                await sleep(100);

                let tvlResults = await printVaults([this.erc20Vault, this.aaveVault], this.tokens);

                this.aTokens.map(async (aToken: any) => {
                    process.stdout.write((await aToken.balanceOf(this.aaveVault.address)).toString() + " ")
                })
                process.stdout.write("\n");
                
                await withSigner(this.subject.address, async (signer) => {
                    await this.aaveVault.connect(signer).pull(this.erc20Vault.address, this.tokensAdresses, tvlResults[1][1], []);
                });

                await printVaults([this.erc20Vault, this.aaveVault], this.tokens);
            });

            it("zero fees", async () => {
                await setZeroFeesFixture();
                let depositAmount = [randomInt(100_0000_0000, 1000_0000_0000), randomInt(100_0000_0000, 1000_0000_0000)];
                
                // console.log("Deployer address:");
                // console.log(this.deployer.address);
                // console.log("other addresses:");
                // console.log(this.admin.address);
                // console.log(this.protocolGovernance.address);
                // console.log(this.subject.address);
                // console.log("Deposit amount is " + depositAmount);
                await this.subject.connect(this.deployer).deposit(depositAmount, 0, []);
                
                let lpAmount = await this.subject.balanceOf(this.deployer.address);
                // console.log("Got " + lpAmount + " LP tokens");
                let depositFilter = this.subject.filters.Deposit(); 
                let deposits = await this.subject.queryFilter(depositFilter);

                // console.log("Actually deposited");
                // let depositedTokens = deposits[0].args["actualTokenAmounts"];
                // console.log(depositedTokens[0].toString() + " " + depositedTokens[1].toString());
                // console.log("Vaults inside:" + (await this.subject.subvaultNfts()).length);
                let targets = [this.erc20Vault, this.aaveVault, this.yearnVault];
                let first = true;
                for (let i = 0; i < 10; i++) {
                    let tvlPromises = targets.map(target => target.tvl());
                    let tvlResults = await Promise.all(tvlPromises);
                    let nonEmptyVaults = targets.filter((target, index) => {
                        return ((tvlResults[index][0][0] > 0) || (tvlResults[index][0][1] > 0))
                    });
                    let {item:from} = randomChoice(nonEmptyVaults);
                    let fromIndex = targets.indexOf(from);
                    let {item:to} = randomChoice(targets.filter((target) => target.address != from.address));
                    let toIndex = targets.indexOf(to); 
                    let pullAmount = this.tokens.map((token, index) => BigNumber.from(tvlResults[fromIndex][0][index]).mul(randomInt(1, 4)).div(3));
                    console.log("Pulling " + pullAmount + " from " + fromIndex + " to " + toIndex);
                    await withSigner(this.subject.address, async (signer) => {
                        let options:any = [];
                        if (to.address == this.uniV3Vault.address) {
                            if (first) {
                                first = false;
                                await this.prepareUniV3Push();
                            }
                            options = encodeToBytes(
                                ["uint256", "uint256", "uint256"],
                                [
                                    ethers.constants.Zero,
                                    ethers.constants.Zero,
                                    ethers.constants.MaxUint256,
                                ]
                            )
                        }
                        if (to.address == this.aaveVault.address) {
                            options = encodeToBytes(
                                ["uint256"],
                                [
                                    ethers.constants.Zero
                                ]
                            )
                        }
                        let actualPulled = await from.connect(signer).callStatic.pull(to.address, this.tokensAdresses, pullAmount, options); 
                        await from.connect(signer).pull(to.address, this.tokensAdresses, pullAmount, options);
                        console.log("Actually pulled " + actualPulled);
                        console.log("");
                    
                    });
                }
                // let allCurrenciesBalancePromises = targets.map(async target => {
                //     let currentBalancesPromises = this.tokens.map(token => token.balanceOf(target.address))
                //     let currentBalancesResults = await Promise.all(currentBalancesPromises);
                //     return currentBalancesResults
                // });
                // let allCurrenciesBalanceResult = await Promise.all(allCurrenciesBalancePromises);
                // console.log("Currencies balances:")
                // for (let i = 0; i < targets.length; i++) {
                //     process.stdout.write(allCurrenciesBalanceResult[i][0].toString() + " " + allCurrenciesBalanceResult[i][1].toString() + " | ");
                // }
                // console.log("transfering to " + this.yearnVault.address);
                // // await withSigner(this.erc20Vault.address, async (signer) => {
                // //     await this.tokens[0].connect(signer).approve(this.yearnVault.address, 99999999);
                // // });
                // // await withSigner(this.erc20Vault.address, async (signer) => {
                // //     await this.tokens[1].connect(signer).approve(this.yearnVault.address, 99999999);
                // // });
                // await withSigner(this.subject.address, async (signer) => {
                //     await this.yearnVault.connect(signer).transferAndPush(this.erc20Vault.address, this.tokensAdresses, [99999999, 99999999], []);
                // });
                // // withSigner(this.subject.address, async (signer) => {
                // //     await this.erc20Vault.connect(signer).pull(this.yearnVault.address, this.tokensAdresses, [99999999, 99999999], []);
                // // });
                // let allCurrenciesBalancePromises1 = targets.map(async target => {
                //     let currentBalancesPromises = this.tokens.map(token => token.balanceOf(target.address))
                //     let currentBalancesResults = await Promise.all(currentBalancesPromises);
                //     return currentBalancesResults
                // });
                // let allCurrenciesBalanceResult1 = await Promise.all(allCurrenciesBalancePromises1);
                // console.log("Currencies balances:")
                // for (let i = 0; i < targets.length; i++) {
                //     process.stdout.write(allCurrenciesBalanceResult1[i][0].toString() + " " + allCurrenciesBalanceResult1[i][1].toString() + " | ");
                // }

                // let actualTokenAmounts = await this.subject.callStatic.withdraw(this.deployer.address, lpAmount, [0, 0], [[], [], [], []]);
                // expect(actualTokenAmounts).to.be.equivalent(depositAmount); 
            });
        });
    }
);
