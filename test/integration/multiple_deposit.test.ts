import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, randomAddress, sleep } from "../library/Helpers";
import { contract } from "../library/setup";
import { pit, RUNS, uint256 } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { integer } from "fast-check";
import { equals, not } from "ramda";
import { ERC20RootVaultGovernance } from "../types";
import { deposit } from "../../tasks/vaults";
import { Address } from "hardhat-deploy/dist/types";
import { randomBytes } from "crypto";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    erc20RootVaultNft: number;
    usdcSupply: BigNumber;
    wethSupply: BigNumber;
    strategyTreasury: Address;
    strategyPerformanceTreasury: Address;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__erc20_yearn",
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

                    this.wethSupply = BigNumber.from(10).pow(6).mul(5);
                    this.usdcSupply = BigNumber.from(10).pow(6).mul(5);

                    await mint("USDC", this.deployer.address, this.usdcSupply);
                    await mint("WETH", this.deployer.address, this.wethSupply);

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
                    // console.log(
                    //     await this.erc20RootVaultGovernance.delayedStrategyParams(
                    //         this.erc20RootVaultNft
                    //     )
                    // );
                    // console.log(
                    //     Number(
                    //         (
                    //             await erc20RootVaultGovernance.delayedStrategyParams(
                    //                 this.erc20RootVaultNft
                    //             )
                    //         ).managementFee
                    //     )
                    // );
                    // console.log(
                    //     Number(
                    //         (
                    //             await erc20RootVaultGovernance.delayedStrategyParams(
                    //                 this.erc20RootVaultNft
                    //             )
                    //         ).performanceFee
                    //     )
                    // );

                    this.strategyTreasury = randomAddress();
                    this.strategyPerformanceTreasury = randomAddress();

                    await erc20RootVaultGovernance
                        .connect(this.admin)
                        .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                            strategyTreasury: this.strategyTreasury,
                            strategyPerformanceTreasury: this.strategyPerformanceTreasury,
                            privateVault: true,
                            managementFee: 0,
                            performanceFee: 0,
                        });
                    await sleep(this.governanceDelay);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .commitDelayedStrategyParams(this.erc20RootVaultNft);
                    console.log(
                        await erc20RootVaultGovernance.delayedStrategyParams(
                            this.erc20RootVaultNft
                        )
                    );
                    // let strategyTreasury = (await this.erc20RootVaultGovernance.delayedStrategyParams(this.erc20RootVaultNft)).strategyTreasury;
                    // let strategyPerformanceTreasury = (await this.erc20RootVaultGovernance.delayedStrategyParams(this.erc20RootVaultNft)).strategyPerformanceTreasury;
                    // let protocolTreasury = await this.protocolGovernance.protocolTreasury();
                    // console.log("\n\nprotocol fee ", Number((await this.erc20RootVaultGovernance.delayedProtocolPerVaultParams(this.erc20RootVaultNft)).protocolFee));
                    // console.log("protocol treasury ", await this.protocolGovernance.protocolTreasury());
                    // console.log(Number(await this.weth.balanceOf(strategyTreasury)));
                    // console.log(Number(await this.weth.balanceOf(strategyPerformanceTreasury)));
                    // console.log(Number(await this.weth.balanceOf(protocolTreasury)));
                    // console.log(Number(await this.usdc.balanceOf(strategyTreasury)));
                    // console.log(Number(await this.usdc.balanceOf(strategyPerformanceTreasury)));
                    // console.log(Number(await this.usdc.balanceOf(protocolTreasury)));
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        pit(
            `
            multiple assymetric deposit + multiple assymetric withdraw with zero fees\n
            sum of deposit[i] = sum of withdraw[j]
        `,
            { numRuns: RUNS.verylow, endOnFailure: true },
            integer({ min: 0, max: 86400 }),
            integer({ min: 1, max: 10 }),
            integer({ min: 1, max: 10 }),
            integer({ min: 100, max: 1_000 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            integer({ min: 10 ** 4, max: 10 ** 5 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            async (
                delay: number,
                numDeposits: number,
                numWithdraws: number,
                amountUSDC: BigNumber,
                amountWETH: BigNumber
            ) => {
                console.log("\nnumDeposits ", numDeposits);
                console.log("numWithdraws ", numWithdraws);
                console.log("amountUSDC ", Number(amountUSDC));
                console.log("amountWETH ", Number(amountWETH));
                for (var i = 0; i < numDeposits; ++i) {
                    await this.subject
                        .connect(this.deployer)
                        .deposit(
                            [
                                BigNumber.from(amountUSDC).div(numDeposits),
                                BigNumber.from(amountWETH).div(numDeposits),
                            ],
                            0
                        );
                }

                const lpTokensAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                console.log("got lp amount ", Number(lpTokensAmount));
                expect(lpTokensAmount).to.not.deep.equals(BigNumber.from(0));

                let erc20_tvl = await this.erc20Vault.tvl();
                let yearn_tvl = await this.yearnVault.tvl();
                let root_tvl = await this.subject.tvl();

                expect(erc20_tvl[0][0].add(yearn_tvl[0][0])).to.deep.equals(
                    root_tvl[0][0]
                );
                expect(erc20_tvl[0][1].add(yearn_tvl[0][1])).to.deep.equals(
                    root_tvl[0][1]
                );

                await sleep(delay);

                let tokenAmounts = [0, 0];
                for (var i = 0; i < numWithdraws; ++i) {
                    let amounts = await this.subject.callStatic.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).div(numWithdraws),
                        [0, 0]
                    );
                    tokenAmounts[0] += Number(amounts[0]);
                    tokenAmounts[1] += Number(amounts[1]);
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).div(numWithdraws),
                        [0, 0]
                    );
                }

                if (
                    !BigNumber.from(lpTokensAmount)
                        .mod(numWithdraws)
                        .eq(BigNumber.from(0))
                ) {
                    let amounts = await this.subject.callStatic.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).mod(numWithdraws),
                        [0, 0]
                    );
                    tokenAmounts[0] += Number(amounts[0]);
                    tokenAmounts[1] += Number(amounts[1]);
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).mod(numWithdraws),
                        [0, 0]
                    );
                }
                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from(0));
                expect(
                    await this.weth.balanceOf(this.deployer.address)
                ).to.be.equal(this.wethSupply);
                expect(
                    await this.usdc.balanceOf(this.deployer.address)
                ).to.be.equal(this.usdcSupply);
                return true;
            }
        );

        const setFeesFixture = deployments.createFixture(async () => {
            await this.deploymentFixture();
            let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                await ethers.getContract("ERC20RootVaultGovernance");

            await erc20RootVaultGovernance
                .connect(this.admin)
                .stageDelayedStrategyParams(this.erc20RootVaultNft, {
                    strategyTreasury:
                        this.strategyTreasury,
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

        pit(
            `
        multiple assymetric deposit + multiple assymetric withdraw with non-zero fees\n
        sum of deposit[i] = sum of withdraw[j] + sum of fees[i]
        `,
            { numRuns: RUNS.verylow, endOnFailure: true },
            integer({ min: 0, max: 86400 }),
            integer({ min: 3, max: 10 }),
            integer({ min: 3, max: 10 }),
            integer({ min: 100, max: 1_000 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            integer({ min: 10 ** 4, max: 10 ** 5 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            async (
                delay: number,
                numDeposits: number,
                numWithdraws: number,
                amountUSDC: BigNumber,
                amountWETH: BigNumber
            ) => {
                await setFeesFixture();
                // console.log("\n\nNEXT ROUND");
                // console.log("weth ", Number(amountWETH));
                // console.log("usdc ", Number(amountUSDC));
                // console.log("deposits ", numDeposits);
                // console.log("withdrawals ", numWithdraws);
                // console.log(
                //     await this.erc20RootVaultGovernance.delayedStrategyParams(
                //         this.erc20RootVaultNft
                //     )
                // );
                for (var i = 0; i < numDeposits; ++i) {
                    await this.subject
                        .connect(this.deployer)
                        .deposit(
                            [
                                BigNumber.from(amountUSDC).div(numDeposits),
                                BigNumber.from(amountWETH).div(numDeposits),
                            ],
                            0
                        );
                }

                // console.log("\n\nAFTER CYCLE DEPOSIT ", Number(this.wethSupply) - Number(await this.weth.balanceOf(this.deployer.address)));
                // console.log("MOD ", Number(amountWETH.mod(numDeposits)));
                let strategyTreasury = (await this.erc20RootVaultGovernance.delayedStrategyParams(this.erc20RootVaultNft)).strategyTreasury;
                let strategyPerformanceTreasury = (await this.erc20RootVaultGovernance.delayedStrategyParams(this.erc20RootVaultNft)).strategyPerformanceTreasury;
                let protocolTreasury = await this.protocolGovernance.protocolTreasury();
                // console.log("protocol fee ", Number((await this.erc20RootVaultGovernance.delayedProtocolPerVaultParams(this.erc20RootVaultNft)).protocolFee));
                // console.log("protocol treasury ", await this.protocolGovernance.protocolTreasury());
                // console.log("\nWETH\n");
                // console.log(Number(await this.weth.balanceOf(this.deployer.address)));
                // console.log(Number(await this.weth.balanceOf(strategyTreasury)));
                // console.log(Number(await this.weth.balanceOf(strategyPerformanceTreasury)));
                // console.log(Number(await this.weth.balanceOf(protocolTreasury)));
                // console.log("\nUSDC\n");
                // console.log(Number(await this.usdc.balanceOf(this.deployer.address)));
                // console.log(Number(await this.usdc.balanceOf(strategyTreasury)));
                // console.log(Number(await this.usdc.balanceOf(strategyPerformanceTreasury)));
                // console.log(Number(await this.usdc.balanceOf(protocolTreasury)));
                // console.log("\nLP\n");
                // console.log(Number(await this.subject.balanceOf(this.deployer.address)));
                // console.log(Number(await this.subject.balanceOf(strategyTreasury)));
                // console.log(Number(await this.subject.balanceOf(strategyPerformanceTreasury)));
                // console.log(Number(await this.subject.balanceOf(protocolTreasury)));
                
                const lpTokensAmount = await this.subject.balanceOf(
                    this.deployer.address
                );
                expect(lpTokensAmount).to.not.deep.equals(BigNumber.from(0));
                expect(
                    await this.weth.balanceOf(this.deployer.address)
                ).to.not.be.equal(this.wethSupply);
                expect(
                    await this.usdc.balanceOf(this.deployer.address)
                ).to.not.be.equal(this.usdcSupply);

                let erc20_tvl = await this.erc20Vault.tvl();
                let yearn_tvl = await this.yearnVault.tvl();
                let root_tvl = await this.subject.tvl();

                expect(erc20_tvl[0][0].add(yearn_tvl[0][0])).to.deep.equals(
                    root_tvl[0][0]
                );
                expect(erc20_tvl[0][1].add(yearn_tvl[0][1])).to.deep.equals(
                    root_tvl[0][1]
                );

                await sleep(delay);

                for (var i = 0; i < numWithdraws; ++i) {
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).div(numWithdraws),
                        [0, 0]
                    );
                }

                if (
                    !BigNumber.from(lpTokensAmount)
                        .mod(numWithdraws)
                        .eq(BigNumber.from(0))
                ) {
                    await this.subject.withdraw(
                        this.deployer.address,
                        BigNumber.from(lpTokensAmount).mod(numWithdraws),
                        [0, 0]
                    );
                }
                if ((await this.subject.balanceOf(strategyTreasury)).gt(0)) {
                    await this.subject.withdraw(
                        strategyTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                }
                if ((await this.subject.balanceOf(strategyPerformanceTreasury)).gt(0)) {
                    await this.subject.withdraw(
                        strategyPerformanceTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                }
                if ((await this.subject.balanceOf(protocolTreasury)).gt(0)) {
                    await this.subject.withdraw(
                        protocolTreasury,
                        BigNumber.from(2).pow(256).sub(1),
                        [0, 0]
                    );
                }
                // console.log("\nFINISH\n");
                // console.log("protocol fee ", Number((await this.erc20RootVaultGovernance.delayedProtocolPerVaultParams(this.erc20RootVaultNft)).protocolFee));
                // console.log("protocol treasury ", await this.protocolGovernance.protocolTreasury());
                // console.log("\nWETH\n");
                // console.log(Number(await this.weth.balanceOf(this.deployer.address)));
                // console.log(Number(await this.weth.balanceOf(strategyTreasury)));
                // console.log(Number(await this.weth.balanceOf(strategyPerformanceTreasury)));
                // console.log(Number(await this.weth.balanceOf(protocolTreasury)));
                // console.log("\nUSDC\n");
                // console.log(Number(await this.usdc.balanceOf(this.deployer.address)));
                // console.log(Number(await this.usdc.balanceOf(strategyTreasury)));
                // console.log(Number(await this.usdc.balanceOf(strategyPerformanceTreasury)));
                // console.log(Number(await this.usdc.balanceOf(protocolTreasury)));
                // console.log("\nLP\n");
                // console.log(Number(await this.subject.balanceOf(this.deployer.address)));
                // console.log(Number(await this.subject.balanceOf(strategyTreasury)));
                // console.log(Number(await this.subject.balanceOf(strategyPerformanceTreasury)));
                // console.log(Number(await this.subject.balanceOf(protocolTreasury)));
                
                expect(
                    (await this.subject.balanceOf(this.deployer.address))
                ).to.deep.equals(BigNumber.from(0));
                expect(
                    (await this.weth.balanceOf(this.deployer.address)).add(await this.weth.balanceOf(strategyTreasury)).add(await this.weth.balanceOf(strategyPerformanceTreasury)).add(await this.weth.balanceOf(protocolTreasury))
                ).to.be.equal(this.wethSupply);
                expect(
                    (await this.usdc.balanceOf(this.deployer.address)).add(await this.usdc.balanceOf(strategyTreasury)).add(await this.usdc.balanceOf(strategyPerformanceTreasury)).add(await this.usdc.balanceOf(protocolTreasury))
                ).to.be.equal(this.usdcSupply);
                return true;
            }
        );
    }
);
