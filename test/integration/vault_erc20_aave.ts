import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, randomAddress, sleep, withSigner } from "../library/Helpers";
import { contract } from "../library/setup";
import { pit, RUNS } from "../library/property";
import {
    ERC20RootVault,
    AaveVault,
    ERC20Vault,
    ProtocolGovernance,
    VaultGovernance,
} from "../types/";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { integer } from "fast-check";
import Exceptions from "../library/Exceptions";
import { ParamsStruct } from "../types/ProtocolGovernance";
import { BigNumberish } from "ethers";

type CustomContext = {
    erc20Vault: ERC20Vault;
    aaveVault: AaveVault;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__erc20_aave",
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
                    let aaveVaultNft = startNft + 1;
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );
                    await setupVault(hre, aaveVaultNft, "AaveVaultGovernance", {
                        createVaultArgs: [tokens, this.deployer.address],
                    });

                    await combineVaults(
                        hre,
                        aaveVaultNft + 1,
                        [erc20VaultNft, aaveVaultNft],
                        this.deployer.address,
                        randomAddress()
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

                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        aaveVaultNft + 1
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

                    // add depositor
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    let currentParams = await this.protocolGovernance.params();
                    let params: ParamsStruct = {
                        maxTokensPerVault: currentParams.maxTokensPerVault,
                        governanceDelay: currentParams.governanceDelay,
                        protocolTreasury: currentParams.protocolTreasury,
                        forceAllowMask: currentParams.forceAllowMask,
                        withdrawLimit: BigNumber.from(20_000_000),
                    };
                    await this.protocolGovernance
                        .connect(this.admin)
                        .stageParams(params);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitParams();

                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10).pow(18).mul(5)
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18).mul(5)
                    );

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    
                    let firstDepositor = randomAddress();
                    let firstUsdcAmount = BigNumber.from(10).pow(4)
                    let firstWethAmount = BigNumber.from(10).pow(10);

                    await mint(
                        "USDC",
                        firstDepositor,
                        firstUsdcAmount
                    );
                    await mint(
                        "WETH",
                        firstDepositor,
                        firstWethAmount
                    );

                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([firstDepositor]);

                    await withSigner(firstDepositor, async (signer) => {

                        await this.weth.connect(signer).approve(
                            this.subject.address,
                            ethers.constants.MaxUint256
                        );
                        await this.usdc.connect(signer).approve(
                            this.subject.address,
                            ethers.constants.MaxUint256
                        );
                        await this.subject
                            .connect(signer)
                            .deposit(
                                [firstUsdcAmount, firstWethAmount],
                                0,
                                []
                        );
                    });

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        pit(
            `
        (balanceOf o deposit) != 0
        (balanceOf o withdraw o sleep o pull o deposit) = 0
        erc20_pull => aave_tvl↑, erc20_tvl↓
        aave_pull => erc20_tvl↑, aave_tvl↓
        tvl_erc20 + tvl_aave = tvl_root
        (tvl_root o (pull_i o pull_i-1 o ...)) = const
        `,
            { numRuns: RUNS.mid },
            integer({ min: 0, max: 86400 }),
            integer({ min: 1, max: 5 }),
            integer({ min: 1, max: 5 }),
            integer({ min: 100_000, max: 1_000_000 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            integer({ min: 10 ** 11, max: 10 ** 15 }).map((x) =>
                BigNumber.from(x.toString())
            ),
            async (
                delay: number,
                rebalanceRatioUSDC: number,
                rebalanceRatioWETH: number,
                amountUSDC: BigNumber,
                amountWETH: BigNumber
            ) => {
                await this.subject
                    .connect(this.deployer)
                    .deposit([amountUSDC, amountWETH], 0, []);

                const lpTokens = await this.subject.balanceOf(
                    this.deployer.address
                );
                expect(lpTokens).to.not.deep.equals(BigNumber.from(0));

                let erc20_tvl = await this.erc20Vault.tvl();
                let aave_tvl = await this.aaveVault.tvl();
                let root_tvl = await this.subject.tvl();

                expect(erc20_tvl[0][0].add(aave_tvl[0][0])).to.deep.equals(
                    root_tvl[0][0]
                );
                expect(erc20_tvl[0][1].add(aave_tvl[0][1])).to.deep.equals(
                    root_tvl[0][1]
                );

                await this.erc20Vault.pull(
                    this.aaveVault.address,
                    [this.usdc.address, this.weth.address],
                    [
                        amountUSDC.div(rebalanceRatioUSDC),
                        amountWETH.div(rebalanceRatioWETH),
                    ],
                    []
                );

                let new_erc20_tvl = await this.erc20Vault.tvl();
                let new_aave_tvl = await this.aaveVault.tvl();
                let new_root_tvl = await this.subject.tvl();

                expect(
                    new_erc20_tvl[0][0].add(new_aave_tvl[0][0])
                ).to.deep.equals(new_root_tvl[0][0]);
                expect(
                    new_erc20_tvl[0][1].add(new_aave_tvl[0][1])
                ).to.deep.equals(new_root_tvl[0][1]);

                if (rebalanceRatioUSDC > 1) {
                    expect(new_erc20_tvl[0][0].lt(erc20_tvl[0][0])).to.be.true;
                    expect(new_aave_tvl[0][0].gt(aave_tvl[0][0])).to.be.true;
                }

                if (rebalanceRatioWETH > 1) {
                    expect(new_erc20_tvl[0][1].lt(erc20_tvl[0][1])).to.be.true;
                    expect(new_aave_tvl[0][1].gt(aave_tvl[0][1])).to.be.true;
                }

                await sleep(delay);
                await this.subject.withdraw(
                    this.deployer.address,
                    lpTokens,
                    [0, 0],
                    [[], []]
                );
                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from(0));

                return true;
            }
        );
    }
);
