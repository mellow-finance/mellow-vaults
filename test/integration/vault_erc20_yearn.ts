import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep } from "../library/Helpers";
import { contract } from "../library/setup";
import { pit, RUNS } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { integer } from "fast-check";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
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
        erc20_pull => yearn_tvl↑, erc20_tvl↓
        yearn_pull => erc20_tvl↑, yearn_tvl↓
        tvl_erc20 + tvl_yearn = tvl_root
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
                    .deposit([amountUSDC, amountWETH], 0);

                const lpTokens = await this.subject.balanceOf(
                    this.deployer.address
                );
                expect(lpTokens).to.not.deep.equals(BigNumber.from(0));

                let erc20_tvl = await this.erc20Vault.tvl();
                let yearn_tvl = await this.yearnVault.tvl();
                let root_tvl = await this.subject.tvl();

                expect(erc20_tvl[0][0].add(yearn_tvl[0][0])).to.deep.equals(
                    root_tvl[0][0]
                );
                expect(erc20_tvl[0][1].add(yearn_tvl[0][1])).to.deep.equals(
                    root_tvl[0][1]
                );

                await this.erc20Vault.pull(
                    this.yearnVault.address,
                    [this.usdc.address, this.weth.address],
                    [
                        amountUSDC.div(rebalanceRatioUSDC),
                        amountWETH.div(rebalanceRatioWETH),
                    ],
                    []
                );

                let new_erc20_tvl = await this.erc20Vault.tvl();
                let new_yearn_tvl = await this.yearnVault.tvl();
                let new_root_tvl = await this.subject.tvl();

                expect(
                    new_erc20_tvl[0][0].add(new_yearn_tvl[0][0])
                ).to.deep.equals(new_root_tvl[0][0]);
                expect(
                    new_erc20_tvl[0][1].add(new_yearn_tvl[0][1])
                ).to.deep.equals(new_root_tvl[0][1]);

                if (rebalanceRatioUSDC > 1) {
                    expect(new_erc20_tvl[0][0].lt(erc20_tvl[0][0])).to.be.true;
                    expect(new_yearn_tvl[0][0].gt(yearn_tvl[0][0])).to.be.true;
                }

                if (rebalanceRatioWETH > 1) {
                    expect(new_erc20_tvl[0][1].lt(erc20_tvl[0][1])).to.be.true;
                    expect(new_yearn_tvl[0][1].gt(yearn_tvl[0][1])).to.be.true;
                }

                await sleep(delay);

                await this.subject.withdraw(
                    this.deployer.address,
                    lpTokens,
                    [0, 0]
                );
                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from(0));

                return true;
            }
        );
    }
);
