import hre, { getNamedAccounts } from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    generateSingleParams,
    mint,
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
import { AaveVault, ERC20RootVaultGovernance, MellowOracle, UniV3Vault } from "../types";
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

                    this.tokens = [this.weth, this.usdc];
                    this.tokensAdresses = this.tokens
                        .map((t) => t.address.toLowerCase())
                        .sort();
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

                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();

                    this.erc20RootVaultNft = yearnVaultNft + 1;
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

            it("zero fees", async () => {
                await setZeroFeesFixture();
                let depositAmount = [randomInt(10000, 100000), randomInt(10000, 100000)];
                
                console.log("Deployer address:");
                console.log(this.deployer.address);
                console.log("other addresses:");
                console.log(this.admin.address);
                console.log(this.protocolGovernance.address);
                console.log(this.subject.address);
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
                let targets = [this.erc20Vault, this.aaveVault, this.uniV3Vault, this.yearnVault];
                for (let i = 0; i < 100; i++) {
                    let iCurrency = randomInt(0, this.tokens.length);
                    // console.log("Currency i is " + iCurrency);
                    let currency = this.tokens[iCurrency];
                    let balancePromises = targets.map(async target => await currency.balanceOf(target.address));
                    let balanceResults = await Promise.all(balancePromises)
                    let nonEmptyVaults = targets.filter((target, index) => 
                        balanceResults[index].gt(0)
                    )
                    // console.log("Non empty vaults length should be 1, but its " + nonEmptyVaults.length);
                    assert(nonEmptyVaults.length != 0);
                    let from = randomChoice(nonEmptyVaults);
                    // console.log(from.address);
                    let to = randomChoice(targets.filter((target) => target !== from));
                    let maxPullAmount = await currency.balanceOf(from.address);
                    let pullAmount = [BigNumber.from(0), BigNumber.from(0)];
                    // console.log(maxPullAmount.toString());
                    pullAmount[iCurrency] = generateSingleParams(uint256).mod(maxPullAmount);
                    withSigner(this.subject.address, async (signer) => {
                        await from.connect(signer).pull(to.address, this.tokensAdresses, pullAmount, []);
                    });
                }

                let actualTokenAmounts = await this.subject.withdraw(this.deployer.address, lpAmount, [0, 0], [[], [], [], []]);
                expect(actualTokenAmounts).to.be.equivalent(depositAmount); 
            });
        });
    }
);
