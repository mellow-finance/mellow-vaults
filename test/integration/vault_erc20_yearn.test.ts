import hre, { getNamedAccounts } from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    randomAddress,
    sleep,
    withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { YearnVault } from "../types/YearnVault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { ParamsStruct } from "../types/ProtocolGovernance";

import { IYearnProtocolVault } from "../types";

type CustomContext = {
    erc20Vault: ERC20Vault;
    yearnVault: YearnVault;
    strategyAddress: string;
    swapRouter: string;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__erc20_yearn_reclaim_tokens",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    const tokens = [this.wbtc.address, this.weth.address]
                        .map((t) => t.toLowerCase())
                        .sort();

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let erc20VaultNft = startNft;
                    let yearnVaultNft = startNft + 1;
                    let erc20RootVaultNft = startNft + 2;

                    // deploying ERC20Vault and its governance
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    // deploying YearnVault and its governance
                    await setupVault(
                        hre,
                        yearnVaultNft,
                        "YearnVaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    this.strategyAddress = randomAddress();
                    // deploying ERC20RootVault and its governance for given ERC20Vault and YearnVault
                    await combineVaults(
                        hre,
                        erc20RootVaultNft,
                        [erc20VaultNft, yearnVaultNft],
                        this.strategyAddress,
                        randomAddress() // startegy treasury
                    );

                    // getting all that vaults addresses
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
                        erc20RootVaultNft
                    );

                    // getting vaults by addresses
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

                    // by default, ERC20RootVault is private, so we need to add deployer to depositorsList, to add him such permission
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    // staging and commiting params for protocol governance
                    let currentParams = await this.protocolGovernance.params();
                    let params: ParamsStruct = {
                        maxTokensPerVault: currentParams.maxTokensPerVault,
                        governanceDelay: currentParams.governanceDelay,
                        protocolTreasury: currentParams.protocolTreasury,
                        forceAllowMask: currentParams.forceAllowMask,
                        withdrawLimit: BigNumber.from(10).pow(6).mul(20),
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

                    const { uniswapV3Router } = await getNamedAccounts();
                    this.swapRouter = uniswapV3Router;
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("When unsupported tokens are minted in the subvault", () => {
            it("reclaimTokens function can transfer them to the zero-vault", async () => {
                const rewardToken = this.usdc;
                const token0 = this.wbtc;
                const token1 = this.weth;

                const token0Amount = BigNumber.from(10).pow(10);
                const token1Amount = BigNumber.from(10).pow(10);
                const rewardAmount = BigNumber.from(10).pow(6);

                // add token0Amount of token0 to balance of deployer
                await mint("WBTC", this.deployer.address, token0Amount);
                // approve transfer from deployer to zeroVault token0Amount of token0
                await token0
                    .connect(this.deployer)
                    .approve(this.subject.address, token0Amount);

                // add token1Amount of token1 to balance of deployer
                await mint("WETH", this.deployer.address, token1Amount);
                // approve transfer from deployer to zeroVault token1Amount of token1
                await token1
                    .connect(this.deployer)
                    .approve(this.subject.address, token1Amount);

                // deposit all given amounts of tokens
                await this.subject.deposit(
                    [token0Amount, token1Amount],
                    BigNumber.from(0),
                    []
                );

                // pull all given amounts of tokens from zero-vault to YearnVault
                await withSigner(this.strategyAddress, async (signer) => {
                    await this.erc20Vault
                        .connect(signer)
                        .pull(
                            this.yearnVault.address,
                            [token0.address, token1.address],
                            [token0Amount, token1Amount],
                            []
                        );
                });

                // check that before the reward is calculated, the amount of reward-token is zero
                {
                    // the amount of the reward-token before the reward is accrued on erc20Vault (zeroVault):
                    const zeroVaultRewardAmount = await rewardToken.balanceOf(
                        this.erc20Vault.address
                    );

                    // the amount of the reward-token before the reward is accrued on yearnVault:
                    const yearnVaultRewardAmount = await rewardToken.balanceOf(
                        this.yearnVault.address
                    );

                    // all these amounts are equal to zero
                    expect(zeroVaultRewardAmount).to.be.eq(BigNumber.from(0));
                    expect(yearnVaultRewardAmount).to.be.eq(BigNumber.from(0));
                }

                // check that after calculating the reward, the number of reward tokens is not zero for YearnVault and zero for ERC20Vault
                {
                    // added some rewardToken to yearnVault as a reward
                    // this operation can be done by some external protocol
                    await mint("USDC", this.yearnVault.address, rewardAmount);

                    // amount of reward-token on zero-vault:
                    const zeroVaultRewardAmount = await rewardToken.balanceOf(
                        this.erc20Vault.address
                    );
                    // amount of reward-token after the reward is accrued on yearnVault:
                    const yearnVaultRewardAmount = await rewardToken.balanceOf(
                        this.yearnVault.address
                    );

                    // amount of reward-token on zeroVault is eqaul to zero
                    expect(zeroVaultRewardAmount).to.be.eq(BigNumber.from(0));
                    // amount of reward-token on yearnVault is equal to `rewardAmount`
                    expect(yearnVaultRewardAmount).to.be.eq(rewardAmount);
                }

                // check that after the reward is reclaimed, the number of reward tokens is zero for ERC20Vault and non-zero for YearnVault
                {
                    const yTokens = await this.yearnVault.yTokens();
                    const yToken0: IYearnProtocolVault =
                        await ethers.getContractAt(
                            "IYearnProtocolVault",
                            yTokens[0]
                        );
                    const yToken1: IYearnProtocolVault =
                        await ethers.getContractAt(
                            "IYearnProtocolVault",
                            yTokens[1]
                        );

                    const amountYToken0BeforeReclaim = await yToken0.balanceOf(
                        this.yearnVault.address
                    );
                    const amountYToken1BeforeReclaim = await yToken1.balanceOf(
                        this.yearnVault.address
                    );

                    // now we returning reward-tokens from yearnVault to zeroVault with a function call:
                    await this.yearnVault.reclaimTokens([
                        rewardToken.address,
                        yToken0.address,
                        yToken1.address,
                    ]);

                    // amount of reward-token on zero-vault:
                    const zeroVaultRewardAmount = await rewardToken.balanceOf(
                        this.erc20Vault.address
                    );
                    // amount of reward-token on yearnVault:
                    const yearnVaultRewardAmount = await rewardToken.balanceOf(
                        this.yearnVault.address
                    );

                    const amountYToken0AfterReclaim = await yToken0.balanceOf(
                        this.yearnVault.address
                    );
                    const amountYToken1AfterReclaim = await yToken1.balanceOf(
                        this.yearnVault.address
                    );

                    // amount of reward-token on zero-vault is equal to `rewardAmount`
                    expect(zeroVaultRewardAmount).to.be.eq(rewardAmount);
                    // amount of reward-token on yearnVault is eqaul to zero
                    expect(yearnVaultRewardAmount).to.be.eq(BigNumber.from(0));

                    // amounts of internal yTokens do not change after reclaim
                    expect(amountYToken0AfterReclaim).to.be.eq(
                        amountYToken0BeforeReclaim
                    );
                    expect(amountYToken1AfterReclaim).to.be.eq(
                        amountYToken1BeforeReclaim
                    );
                }

                // swap reward-token to both of vault-tokens
                {
                    // amount of reward-token on zero-vault:
                    const zeroVaultRewardAmountBeforeSwap =
                        await rewardToken.balanceOf(this.erc20Vault.address);

                    // amount of reward-token on zero-vault:
                    const zeroVaultToken0AmountBeforeSwap =
                        await token0.balanceOf(this.erc20Vault.address);

                    // amount of reward-token on zero-vault:
                    const zeroVaultToken1AmountBeforeSwap =
                        await token1.balanceOf(this.erc20Vault.address);

                    const APPROVE_SELECTOR = "0x095ea7b3";
                    const EXACT_INPUT_SINGLE_SELECTOR = "0x414bf389";

                    // function to perform a swap using an external call to swapRouter
                    const makeSwap = async (
                        amountIn: BigNumber,
                        tokenIn: string,
                        tokenOut: string
                    ) => {
                        await withSigner(
                            this.strategyAddress,
                            async (signer) => {
                                // done in the same way as in MStrategy

                                // approve amount for transfer
                                await this.erc20Vault
                                    .connect(signer)
                                    .externalCall(
                                        rewardToken.address,
                                        APPROVE_SELECTOR,
                                        encodeToBytes(
                                            ["address", "uint256"],
                                            [this.swapRouter, amountIn]
                                        )
                                    );

                                const swapParams = {
                                    tokenIn: tokenIn,
                                    tokenOut: tokenOut,
                                    fee: 3000,
                                    recipient: this.erc20Vault.address,
                                    deadline: ethers.constants.MaxUint256,
                                    amountIn: amountIn,
                                    amountOutMinimum: 0,
                                    sqrtPriceLimitX96: 0,
                                };

                                // make a swap with swapRouter
                                await this.erc20Vault
                                    .connect(signer)
                                    .externalCall(
                                        this.swapRouter,
                                        EXACT_INPUT_SINGLE_SELECTOR,
                                        encodeToBytes(
                                            [
                                                "tuple(" +
                                                    "address tokenIn, " +
                                                    "address tokenOut, " +
                                                    "uint24 fee, " +
                                                    "address recipient, " +
                                                    "uint256 deadline, " +
                                                    "uint256 amountIn, " +
                                                    "uint256 amountOutMinimum, " +
                                                    "uint160 sqrtPriceLimitX96)",
                                            ],
                                            [swapParams]
                                        )
                                    );

                                // reduce approval
                                await this.erc20Vault
                                    .connect(signer)
                                    .externalCall(
                                        rewardToken.address,
                                        APPROVE_SELECTOR,
                                        encodeToBytes(
                                            ["address", "uint256"],
                                            [this.swapRouter, BigNumber.from(0)]
                                        )
                                    );
                            }
                        );
                    };

                    // swap half of reward-tokens to token0
                    await makeSwap(
                        rewardAmount.div(2),
                        rewardToken.address,
                        token0.address
                    );

                    // and swap half of reward-tokens to token1
                    await makeSwap(
                        rewardAmount.div(2),
                        rewardToken.address,
                        token1.address
                    );

                    // amount of reward-token on zero-vault:
                    const zeroVaultRewardAmountAfterSwap =
                        await rewardToken.balanceOf(this.erc20Vault.address);

                    // amount of reward-token on zero-vault:
                    const zeroVaultToken0AmountAfterSwap =
                        await token0.balanceOf(this.erc20Vault.address);

                    // amount of reward-token on zero-vault:
                    const zeroVaultToken1AmountAfterSwap =
                        await token1.balanceOf(this.erc20Vault.address);

                    // amount of reward-token before swap must to be equal to `rewardAmount`
                    expect(zeroVaultRewardAmountBeforeSwap).to.be.eq(
                        rewardAmount
                    );
                    // amount of reward-token after swap must to be equal to zero
                    expect(zeroVaultRewardAmountAfterSwap).to.be.eq(
                        BigNumber.from(0)
                    );

                    // amount of token0 before swap must to be equal to zero
                    expect(zeroVaultToken0AmountBeforeSwap).to.be.eq(
                        BigNumber.from(0)
                    );
                    // amount of token0 after swap must to be greater than zero
                    expect(zeroVaultToken0AmountAfterSwap).to.be.gt(
                        BigNumber.from(0)
                    );

                    // amount of token1 before swap must to be equal to zero
                    expect(zeroVaultToken1AmountBeforeSwap).to.be.eq(
                        BigNumber.from(0)
                    );
                    // amount of token1 after swap must to be greater than zero
                    expect(zeroVaultToken1AmountAfterSwap).to.be.gt(
                        BigNumber.from(0)
                    );
                }
            });
        });
    }
);
