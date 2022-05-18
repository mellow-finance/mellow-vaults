import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    sleep,
    mintUniV3Position_USDC_WETH,
    randomAddress,
    addSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { UniV3Vault } from "../types/UniV3Vault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults, ALLOW_MASK } from "../../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";

import {
    ERC20RootVaultGovernance,
    IVaultRegistry,
    ISwapRouter as SwapRouterInterface,
    IUniswapV3Pool,
} from "../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { randomInt } from "crypto";
import Common from "../library/Common";
import { withdraw } from "../../tasks/vaults";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
    positionManager: Contract;
    swapRouter: SwapRouterInterface;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__erc20_univ3",
    function () {
        const uniV3PoolFee = 3000;

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    const { uniswapV3PositionManager } =
                        await getNamedAccounts();

                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let uniV3VaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                uniV3PoolFee,
                            ],
                        }
                    );
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20VaultNft + 1,
                        [erc20VaultNft, uniV3VaultNft],
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
                        uniV3VaultNft
                    );

                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft + 1
                    );

                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );
                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );
                    this.uniV3Vault = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    );
                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    // add depositor
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18)
                    );

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    const { uniswapV3Router } = await getNamedAccounts();
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

        describe("rebalance", () => {
            it("initializes uniV3 vault with position nft and increases tvl respectivly", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });

                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result.tokenId
                );
                const uniV3Tvl = await this.uniV3Vault.tvl();
                expect(uniV3Tvl).to.not.contain(0);
                expect(await this.erc20Vault.tvl()).to.deep.equals([
                    [BigNumber.from(0), BigNumber.from(0)],
                    [BigNumber.from(0), BigNumber.from(0)],
                ]);
            });

            it("deposits", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
                await this.subject.deposit(
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    0,
                    []
                );
                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from("1000000000000000000"));
            });

            it("pulls univ3 to erc20 and collects earnings", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });

                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
                await this.subject.deposit(
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    0,
                    []
                );
                await this.uniV3Vault.collectEarnings();
                await this.uniV3Vault.pull(
                    this.erc20Vault.address,
                    [this.usdc.address, this.weth.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    []
                );
            });

            it("replaces univ3 position", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });

                const { deployer, weth, usdc } = await getNamedAccounts();
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](deployer, this.uniV3Vault.address, result.tokenId);
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result.tokenId
                );
                await this.uniV3Vault.pull(
                    this.erc20Vault.address,
                    [usdc, weth],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    []
                );
                const result2 = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](deployer, this.uniV3Vault.address, result2.tokenId);
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result2.tokenId
                );
            });

            const setZeroFeesFixture = deployments.createFixture(async () => {
                await this.deploymentFixture();
                let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                    await ethers.getContract("ERC20RootVaultGovernance");

                let erc20VaultNft = await this.subject.nft();

                await erc20RootVaultGovernance
                    .connect(this.admin)
                    .stageDelayedStrategyParams(erc20VaultNft, {
                        strategyTreasury: randomAddress(),
                        strategyPerformanceTreasury: randomAddress(),
                        privateVault: true,
                        managementFee: BigNumber.from(0),
                        performanceFee: BigNumber.from(0),
                        depositCallbackAddress: ethers.constants.AddressZero,
                        withdrawCallbackAddress: ethers.constants.AddressZero,
                    });
                await sleep(this.governanceDelay);

                await this.erc20RootVaultGovernance
                    .connect(this.admin)
                    .commitDelayedStrategyParams(erc20VaultNft);

                const { protocolTreasury } = await getNamedAccounts();
                await this.protocolGovernance.connect(this.admin).stageParams({
                    forceAllowMask: ALLOW_MASK,
                    maxTokensPerVault: 10,
                    governanceDelay: 86400,
                    protocolTreasury,
                    withdrawLimit: BigNumber.from(10).pow(20),
                });
                await sleep(this.governanceDelay);
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitParams();
            });

            const setApprovedSignerForNft = async (
                nft: BigNumber,
                signer: SignerWithAddress
            ) => {
                let internalParams =
                    await this.erc20VaultGovernance.internalParams();
                let registry: IVaultRegistry = await ethers.getContractAt(
                    "IVaultRegistry",
                    internalParams.registry
                );

                await registry
                    .connect(this.admin)
                    .adminApprove(signer.address, nft);
            };

            const addLiquidity = async (
                signer: SignerWithAddress,
                usdcAmount: BigNumber,
                wethAmount: BigNumber
            ) => {
                await mint("USDC", signer.address, usdcAmount);
                await mint("WETH", signer.address, wethAmount);

                await this.subject
                    .connect(signer)
                    .deposit([usdcAmount, wethAmount], BigNumber.from(0), []);
                await setApprovedSignerForNft(
                    await this.erc20Vault.nft(),
                    signer
                );

                await this.erc20Vault
                    .connect(signer)
                    .pull(
                        this.uniV3Vault.address,
                        [this.usdc.address, this.weth.address],
                        [usdcAmount, wethAmount],
                        []
                    );
            };

            const getLiquidity = async (signer: SignerWithAddress) => {
                await setApprovedSignerForNft(
                    await this.uniV3Vault.nft(),
                    signer
                );

                const usdcBalanceBefore = await this.usdc
                    .connect(this.admin)
                    .balanceOf(signer.address);
                const wethBalanceBefore = await this.weth
                    .connect(this.admin)
                    .balanceOf(signer.address);

                await this.subject.connect(signer).withdraw(
                    signer.address,
                    ethers.constants.MaxUint256, // take all liquidity, that user has
                    [BigNumber.from(0), BigNumber.from(0)],
                    [[], []]
                );

                const usdcBalanceAfter = await this.usdc
                    .connect(this.admin)
                    .balanceOf(signer.address);
                const wethBalanceAfter = await this.weth
                    .connect(this.admin)
                    .balanceOf(signer.address);

                return {
                    usdc: usdcBalanceAfter.sub(usdcBalanceBefore),
                    weth: wethBalanceAfter.sub(wethBalanceBefore),
                };
            };

            const getSqrtPriceX96 = async () => {
                const poolAddress = await this.uniV3Vault.pool();
                const pool: IUniswapV3Pool = await ethers.getContractAt(
                    "IUniswapV3Pool",
                    poolAddress
                );
                return (await pool.slot0()).sqrtPriceX96;
            };

            const push = async (
                delta: BigNumber,
                from: string,
                to: string,
                tokenName: string
            ) => {
                const n = 20;
                var amounts: BigNumber[] = [];
                var used = BigNumber.from(0);
                for (var i = 0; i < 20; i++) {
                    amounts.push(delta.div(n));
                    used = used.add(amounts[i]);
                }
                amounts[0] = amounts[0].add(delta.sub(used));

                await mint(tokenName, this.deployer.address, delta);
                for (var i = 0; i < n; i++) {
                    await this.swapRouter.exactInputSingle({
                        tokenIn: from,
                        tokenOut: to,
                        fee: uniV3PoolFee,
                        recipient: this.deployer.address,
                        deadline: ethers.constants.MaxUint256,
                        amountIn: amounts[i],
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0,
                    });
                }
            };

            const pushPriceDown = async (delta: BigNumber) => {
                await push(delta, this.usdc.address, this.weth.address, "USDC");
            };

            const pushPriceUp = async (delta: BigNumber) => {
                await push(delta, this.weth.address, this.usdc.address, "WETH");
            };
            for (
                var numberOfDepositors = 2;
                numberOfDepositors <= 128;
                numberOfDepositors *= 2
            ) {
                it.only(`multiple deposits for different number of depositors = ${numberOfDepositors}`, async () => {
                    await setZeroFeesFixture();
                    var depositors: SignerWithAddress[] = [];
                    var deposited: { usdc: BigNumber; weth: BigNumber }[] = [];
                    var withdrawed: { usdc: BigNumber; weth: BigNumber }[] = [];
                    for (var i = 0; i < numberOfDepositors; i++) {
                        depositors.push(await addSigner(randomAddress()));
                        deposited.push({
                            usdc: BigNumber.from(0),
                            weth: BigNumber.from(0),
                        });
                        withdrawed.push({
                            usdc: BigNumber.from(0),
                            weth: BigNumber.from(0),
                        });

                        for (var address of [
                            this.subject.address,
                            this.uniV3Vault.address,
                            this.erc20Vault.address,
                        ]) {
                            await this.weth
                                .connect(depositors[i])
                                .approve(address, ethers.constants.MaxUint256);
                            await this.usdc
                                .connect(depositors[i])
                                .approve(address, ethers.constants.MaxUint256);
                        }
                    }

                    console.log("Approved");
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist(
                            depositors.map((x) => x.address)
                        );

                    const result = await mintUniV3Position_USDC_WETH({
                        fee: uniV3PoolFee,
                        tickLower: -887220,
                        tickUpper: 887220,
                        usdcAmount: BigNumber.from(10).pow(4),
                        wethAmount: BigNumber.from(10).pow(6),
                    });

                    const { deployer } = await getNamedAccounts();
                    await this.positionManager.functions[
                        "safeTransferFrom(address,address,uint256)"
                    ](deployer, this.uniV3Vault.address, result.tokenId);
                    console.log("univ3nft minted");
                    const firstUserDepositUsdc = BigNumber.from(10)
                        .pow(6)
                        .mul(3000);
                    const firstUserDepositWeth = BigNumber.from(10).pow(18);

                    await addLiquidity(
                        depositors[0],
                        firstUserDepositUsdc,
                        firstUserDepositWeth
                    );
                    deposited[0] = {
                        usdc: firstUserDepositUsdc,
                        weth: firstUserDepositWeth,
                    };

                    const numberOfIterations = Math.max(
                        100,
                        numberOfDepositors * 4
                    );
                    const initialPrice = await getSqrtPriceX96();
                    for (
                        var iteration = 0;
                        iteration < numberOfIterations;
                        iteration++
                    ) {
                        var signerIndex = randomInt(depositors.length - 1) + 1;
                        var signer = depositors[signerIndex];
                        var usdcDepositRatio = randomInt(80) + 20;
                        var wethDepositRatio = randomInt(80) + 20;
                        const usdcDeposit = firstUserDepositUsdc
                            .mul(usdcDepositRatio)
                            .div(100);
                        const wethDeposit = firstUserDepositWeth
                            .mul(wethDepositRatio)
                            .div(100);
                        await addLiquidity(signer, usdcDeposit, wethDeposit);
                        deposited[signerIndex].usdc =
                            deposited[signerIndex].usdc.add(usdcDeposit);
                        deposited[signerIndex].weth =
                            deposited[signerIndex].weth.add(wethDeposit);
                        if (iteration < numberOfIterations / 2) {
                            await pushPriceDown(BigNumber.from(10).pow(14));
                        } else {
                            await pushPriceUp(
                                BigNumber.from(10).pow(21).div(3)
                            );
                        }
                    }

                    console.log("deposited");
                    for (var pwr = 0; pwr < 30; pwr++) {
                        const k = BigNumber.from(2).pow(pwr);
                        let currentPrice = await getSqrtPriceX96();
                        if (currentPrice.gt(initialPrice)) {
                            while (currentPrice.gt(initialPrice)) {
                                await pushPriceDown(
                                    BigNumber.from(10).pow(13).div(k)
                                );
                                currentPrice = await getSqrtPriceX96();
                            }
                        } else {
                            while (currentPrice.lt(initialPrice)) {
                                await pushPriceUp(
                                    BigNumber.from(10).pow(22).div(3).div(k)
                                );
                                currentPrice = await getSqrtPriceX96();
                            }
                        }
                    }

                    console.log("balanced");

                    for (var i = depositors.length - 1; i >= 0; i--) {
                        await getLiquidity(depositors[i]);
                        withdrawed[i].usdc = await this.usdc
                            .connect(this.admin)
                            .balanceOf(depositors[i].address);
                        withdrawed[i].weth = await this.weth
                            .connect(this.admin)
                            .balanceOf(depositors[i].address);
                    }

                    console.log("Number of depositors:", numberOfDepositors);
                    console.log("Number of iterations:", numberOfIterations);
                    for (var i = 0; i < numberOfDepositors; i++) {
                        const depositUsdc = deposited[i].usdc;
                        const depositWeth = deposited[i].weth;
                        const withdrawUsdc = withdrawed[i].usdc;
                        const withdrawWeth = withdrawed[i].weth;
                        let result: string = `depositor ${i + 1}`;
                        if (depositUsdc.eq(0)) {
                            result += " has no operations";
                        } else {
                            const usdcDelta =
                                withdrawUsdc
                                    .mul(100000)
                                    .div(depositUsdc)
                                    .sub(100000)
                                    .toNumber() / 1000;
                            const wethDelta =
                                withdrawWeth
                                    .mul(100000)
                                    .div(depositWeth)
                                    .sub(100000)
                                    .toNumber() / 1000;
                            result += `\tusdc delta: ${usdcDelta}%,\tweth delta: ${wethDelta}%`;
                        }
                        console.log(result);
                    }
                    console.log("----------------------------------");
                });
            }
        });
    }
);
