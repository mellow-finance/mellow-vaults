import { expect } from "chai";
import hre from "hardhat";
import { ethers, deployments, getNamedAccounts } from "hardhat";

import { contract } from "./library/setup";
import {
    ERC20Vault,
    SStrategy,
    MockCowswap,
    MockOracle,
    UniV3Vault,
    RequestableRootVault,
    SqueethVault,
} from "./types";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { abi as ICurvePool } from "./helpers/curvePoolABI.json";
import { abi as IWETH } from "./helpers/wethABI.json";
import { abi as IWSTETH } from "./helpers/wstethABI.json";
import { generateSingleParams, mint, randomAddress, sleep, uniSwapTokensGivenInput, withSigner } from "./library/Helpers";
import { BigNumber } from "ethers";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import Exceptions from "./library/Exceptions";
import { ERC20 } from "./library/Types";
import { randomBytes } from "ethers/lib/utils";
import { TickMath } from "@uniswap/v3-sdk";
import { sqrt } from "@uniswap/sdk-core";
import JSBI from "jsbi";
import { uint256 } from "./library/property";

type CustomContext = {
    erc20Vault: ERC20Vault;
    squeethVault: SqueethVault;
    rootVault: RequestableRootVault;
};

type DeployOptions = {};

contract<SStrategy, DeployOptions, CustomContext>("SStrategy", function () {
    const uniV3PoolFee = 500;
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { uniswapV3PositionManager, uniswapV3Router } =
                    await getNamedAccounts();

                let strategyTreasury = randomAddress();

                this.swapRouter = await ethers.getContractAt(
                    ISwapRouter,
                    uniswapV3Router
                );

                const tokens = [this.weth.address]

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let erc20VaultNft = startNft;
                let squeethVaultNft = startNft + 1;
                let rootVaultNft = startNft + 2;
                await setupVault(
                    hre,
                    erc20VaultNft,
                    "ERC20VaultGovernance",
                    {
                        createVaultArgs: [
                            tokens,
                            this.deployer.address
                        ],
                    }
                );
                
                await setupVault(
                    hre,
                    squeethVaultNft,
                    "SqueethVaultGovernance",
                    {
                        createVaultArgs: [
                            this.deployer.address
                        ],
                    }
                );

                const { deploy } = deployments;

                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const squeethVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    squeethVaultNft
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.squeethVault = await ethers.getContractAt(
                    "SqueethVault",
                    squeethVault
                );


                let strategyDeployParams = await deploy("SStrategy", {
                    from: this.deployer.address,
                    contract: "SStrategy",
                    args: [
                        this.weth.address,
                        this.erc20Vault.address,
                        this.squeethVault.address,
                        this.swapRouter.address,
                        this.deployer.address
                    ],
                    log: true,
                    autoMine: true,
                });

                await combineVaults(
                    hre,
                    rootVaultNft,
                    [erc20VaultNft, squeethVaultNft],
                    strategyDeployParams.address,
                    strategyTreasury,
                    undefined, 
                    "RequestableRootVault"
                );
                

                const requestableRootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    rootVaultNft
                );

                this.rootVault = await ethers.getContractAt(
                    "RequestableRootVault",
                    requestableRootVault
                );
                

                //TODO: validator

                this.subject = await ethers.getContractAt(
                    "SStrategy",
                    strategyDeployParams.address
                );

                await this.subject.setRootVault(this.rootVault.address);
                
                await mint(
                    "WETH",
                    this.subject.address,
                    BigNumber.from(10).pow(18).mul(100)
                );
                await mint(
                    "WETH",
                    this.deployer.address,
                    BigNumber.from(10).pow(18).mul(100)
                );

                await this.subject.updateStrategyParams({
                    lowerHedgingThresholdD9: BigNumber.from(10).pow(8).mul(5),
                    upperHedgingThresholdD9: BigNumber.from(10).pow(9).mul(2),
                    cycleDuration: BigNumber.from(3600).mul(24).mul(28),
                });

                await this.subject.updateLiquidationParams({
                    lowerLiquidationThresholdD9: BigNumber.from(10).pow(8).mul(5), 
                    upperLiquidationThresholdD9: BigNumber.from(10).pow(8).mul(18),
                });

                await this.subject.updateOracleParams({
                    maxTickDeviation: BigNumber.from(100),
                    slippageD9: BigNumber.from(10).pow(7),
                    oracleObservationDelta: BigNumber.from(15 * 60),
                });
                this.firstDepositor = randomAddress();
                this.firstDepositAmount = BigNumber.from(10).pow(12);
                await mint(
                    "WETH",
                    this.firstDepositor,
                    BigNumber.from(10).pow(18).mul(100)
                );
                await this.rootVault.connect(this.admin).addDepositorsToAllowlist([this.firstDepositor]);

                await withSigner(this.firstDepositor, async (s) => {
                    await this.weth.connect(s).approve(this.rootVault.address, this.firstDepositAmount)
                    await this.rootVault.connect(s).deposit([this.firstDepositAmount], 0, randomBytes(4));
                });

                this.depositor = randomAddress();
                this.depositAmount = generateSingleParams(uint256).mod(BigNumber.from(10).pow(18).mul(90)).add(BigNumber.from(10).pow(18).mul(10));
                await mint(
                    "WETH",
                    this.depositor,
                    BigNumber.from(10).pow(18).mul(100)
                );
                await withSigner(this.depositor, async (s) => {
                    await this.weth.connect(s).approve(this.rootVault.address, this.depositAmount)
                });

                await this.rootVault.connect(this.admin).addDepositorsToAllowlist([this.depositor]);
                
                this.safe = randomAddress();
                await mint(
                    "WETH",
                    this.safe,
                    BigNumber.from(10).pow(18).mul(100)
                );

                let allowAllValidator = await ethers.getContract("AllowAllValidator");
                await this.protocolGovernance.connect(this.admin).stageValidator(this.weth.address, allowAllValidator.address);
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitValidator(this.weth.address);
                
                
                this.uniV3Oracle = await ethers.getContract(
                    "UniV3Oracle"
                );

                await this.uniV3Oracle.connect(this.admin).addUniV3Pools([await this.squeethVault.wPowerPerpPool()]);

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("temp", () => {
        it("deposits work", async() => {
            let baseWeth = await this.weth.balanceOf(this.squeethVault.address);
            expect((await this.weth.balanceOf(this.depositor)).gt(this.depositAmount)).to.be.true;
            
            let deposited = BigNumber.from(0);
            await withSigner(this.depositor, async (s) => {
                deposited = (await this.rootVault.connect(s).callStatic.deposit([this.depositAmount], 0, randomBytes(4)))[0];
                await this.rootVault.connect(s).deposit([this.depositAmount], 0, randomBytes(4));
            })
            expect((await this.weth.balanceOf(this.squeethVault.address)).eq(deposited.add(baseWeth))).to.be.true;
        })
        it("withdraw does nothing without registering", async () => {
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).deposit([this.depositAmount], 0, randomBytes(4));
                let wethBefore = await this.weth.balanceOf(this.depositor)
                await this.rootVault.connect(s).withdraw(this.depositor, [randomBytes(4), randomBytes(4)]);
                expect((await this.weth.balanceOf(this.depositor)).eq(wethBefore)).to.be.true;
            })
        })
        it("withdraws after registering", async () => {
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).deposit([this.depositAmount], 0, randomBytes(4));
                let wethBefore = await this.weth.balanceOf(this.depositor)
                let lpAmount = await this.rootVault.balanceOf(this.depositor);
                await this.rootVault.connect(s).registerWithdrawal(lpAmount);
                await sleep(3600 * 24 * 30);
                await this.rootVault.connect(s).invokeExecution();
                let withdrawn = await this.rootVault.connect(s).callStatic.withdraw(this.depositor, [randomBytes(4), randomBytes(4)]);
                await this.rootVault.connect(s).withdraw(this.depositor, [randomBytes(4), randomBytes(4)]);
                expect((await this.weth.balanceOf(this.depositor)).gt(wethBefore)).to.be.true;
            })
        })
    })

    describe("full cycle", () => {
        beforeEach(async () => {
            await withSigner(this.depositor, async (s) => {
                await this.rootVault.connect(s).deposit([this.depositAmount], 0, randomBytes(4));
            })
        });

        it("start", async () => {
            let currentEthPrice = await this.squeethVault.twapIndexPrice();
            let tvlBefore = await this.rootVault.tvl();
            console.log(tvlBefore.toString());
            await this.subject.startCycleMocked(currentEthPrice, BigNumber.from(10).pow(18).mul(100), this.safe);
            let tvlAfter = await this.rootVault.tvl();
            expect(tvlAfter[0][0].lt(tvlBefore[0][0])).to.be.true;
            expect(tvlAfter[0][1].lt(tvlBefore[0][1])).to.be.true;
        })

        // it.only("option has no value", async () => {
        //     let currentEthPrice = await this.squeethVault.twapIndexPrice();
        //     await this.subject.startCycleMocked(currentEthPrice, BigNumber.from(10).pow(18).mul(100), this.safe);

        //     await withSigner(this.safe, async (s) => {
        //         await this.weth.connect(s).approve(this.squeethVault.address, BigNumber.from(10).pow(18).mul(100));
        //     })
        //     console.log((await this.squeethVault.twapIndexPrice()).toString());
        //     await uniSwapTokensGivenInput(this.swapRouter, [this.usdc, this.weth], 3000, true, BigNumber.from(10).pow(18).mul(100));
        //     await sleep(3600 * 24 * 30);
        //     console.log((await this.squeethVault.twapIndexPrice()).toString());
        //     await this.subject.endCycleMocked(this.safe);

        // })
    })

});
