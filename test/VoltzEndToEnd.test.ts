import { deployments, ethers, getNamedAccounts, network } from "hardhat";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import {
    addSigner,
    mint,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20Vault,
    IMarginEngine,
    IPeriphery,
    IRateOracle,
    IVAMM,
    LPOptimiserStrategy,
    VoltzVault,
} from "./types";
import hre from "hardhat";
import { BigNumber, utils } from "ethers";
import { expect } from "chai";

type CustomContext = {
    strategy: LPOptimiserStrategy;
    voltzVaults: VoltzVault[];
    erc20Vault: ERC20Vault;
    preparePush: () => any;
    marginEngine: string;
    marginEngineContract: IMarginEngine;
    vammContract: IVAMM;
};

type DeployOptions = {};

contract<{}, DeployOptions, CustomContext>("Voltz E2E", function () {
    const MIN_SQRT_RATIO = BigNumber.from("2503036416286949174936592462");
    const MAX_SQRT_RATIO = BigNumber.from("2507794810551837817144115957740");

    this.timeout(200000);

    const leverage = 2.2;
    const marginMultiplierPostUnwind = 2;
    const noOfVoltzVaults = 2;
    const vaultWithdrawalOptions = [[], [], []];

    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { marginEngine, voltzPeriphery } =
                    await getNamedAccounts();

                this.periphery = voltzPeriphery;
                this.peripheryContract = (await ethers.getContractAt(
                    "IPeriphery",
                    this.periphery
                )) as IPeriphery;

                this.marginEngine = marginEngine;
                this.marginEngineContract = (await ethers.getContractAt(
                    "IMarginEngine",
                    this.marginEngine
                )) as IMarginEngine;

                this.vamm = await this.marginEngineContract.vamm();
                this.vammContract = (await ethers.getContractAt(
                    "IVAMM",
                    this.vamm
                )) as IVAMM;

                this.rateOracle = await this.marginEngineContract.rateOracle();
                this.rateOracleContract = (await ethers.getContractAt(
                    "IRateOracle",
                    this.rateOracle
                )) as IRateOracle;

                await this.usdc.approve(
                    this.marginEngine,
                    ethers.constants.MaxUint256
                );

                await this.protocolGovernance
                    .connect(this.admin)
                    .stagePermissionGrants(this.usdc.address, [
                        PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                    ]);
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitPermissionGrants(this.usdc.address);

                const tokens = [this.usdc.address].map((t) => t.toLowerCase());

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let voltzVaultNfts = Array.from(
                    Array(noOfVoltzVaults).keys()
                ).map((val) => startNft + val);
                let erc20VaultNft = startNft + noOfVoltzVaults;

                this.voltzVaultHelperSingleton = (
                    await ethers.getContract("VoltzVaultHelper")
                ).address;

                const currentTick = (await this.vammContract.vammVars()).tick;
                this.initialTickLow = currentTick - (currentTick % 60) - 600;
                this.initialTickHigh = currentTick - (currentTick % 60) + 600;

                for (let nft of voltzVaultNfts) {
                    await setupVault(hre, nft, "VoltzVaultGovernance", {
                        createVaultArgs: [
                            tokens,
                            this.deployer.address,
                            this.marginEngine,
                            this.voltzVaultHelperSingleton,
                            {
                                tickLower: this.initialTickLow,
                                tickUpper: this.initialTickHigh,
                                leverageWad: utils.parseEther(
                                    leverage.toString()
                                ),
                                marginMultiplierPostUnwindWad: utils.parseEther(
                                    marginMultiplierPostUnwind.toString()
                                ),
                            },
                        ],
                    });
                }

                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                const { deploy } = deployments;

                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.voltzVaults = [];
                for (let i = 0; i < noOfVoltzVaults; i++) {
                    const voltzVaultAddress = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        voltzVaultNfts[i]
                    );

                    const voltzVault = await ethers.getContractAt(
                        "VoltzVault",
                        voltzVaultAddress
                    );

                    this.voltzVaults.push(voltzVault as VoltzVault);
                }

                let strategyDeployParams = await deploy("LPOptimiserStrategy", {
                    from: this.deployer.address,
                    contract: "LPOptimiserStrategy",
                    args: [
                        this.erc20Vault.address,
                        this.voltzVaults.map((val) => val.address),
                        this.voltzVaults.map((_, index) => {
                            return {
                                sigmaWad: "100000000000000000",
                                maxPossibleLowerBoundWad: "1500000000000000000",
                                proximityWad: "100000000000000000",
                                weight: index === 0 ? "1" : "0",
                            };
                        }),
                        this.admin.address,
                    ],
                    log: true,
                    autoMine: true,
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft].concat(voltzVaultNfts),
                    this.deployer.address,
                    this.deployer.address
                );

                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
                );

                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

                let usdcValidator = await deploy("ERC20Validator", {
                    from: this.deployer.address,
                    contract: "ERC20Validator",
                    args: [this.protocolGovernance.address],
                    log: true,
                    autoMine: true,
                });

                await this.protocolGovernance
                    .connect(this.admin)
                    .stageValidator(this.usdc.address, usdcValidator.address);
                await sleep(await this.protocolGovernance.governanceDelay());
                await this.protocolGovernance
                    .connect(this.admin)
                    .commitValidator(this.usdc.address);

                this.strategy = await ethers.getContractAt(
                    "LPOptimiserStrategy",
                    strategyDeployParams.address
                );

                this.strategySigner = await addSigner(this.strategy.address);

                await this.voltzVaultGovernance
                    .connect(this.admin)
                    .stageDelayedProtocolParams({
                        periphery: voltzPeriphery,
                    });
                await sleep(86400);
                await this.voltzVaultGovernance
                    .connect(this.admin)
                    .commitDelayedProtocolParams();

                this.preparePush = async () => {
                    await withSigner(
                        "0xb527e950fc7c4f581160768f48b3bfa66a7de1f0",
                        async (s) => {
                            await expect(
                                this.marginEngineContract
                                    .connect(s)
                                    .setIsAlpha(false)
                            ).to.not.be.reverted;

                            await expect(
                                this.vammContract.connect(s).setIsAlpha(false)
                            ).to.not.be.reverted;
                        }
                    );
                };

                this.grantPermissionsVoltzVaults = async () => {
                    let tokenIds: string[] = [];
                    for (let vault of this.voltzVaults) {
                        let tokenId = await ethers.provider.send(
                            "eth_getStorageAt",
                            [
                                vault.address,
                                "0x4", // address of _nft
                            ]
                        );
                        tokenIds.push(tokenId);
                    }

                    tokenIds.push(
                        await ethers.provider.send("eth_getStorageAt", [
                            this.erc20Vault.address,
                            "0x4", // address of _nft
                        ])
                    );

                    await withSigner(
                        this.erc20RootVault.address,
                        async (erc20RootVaultSigner) => {
                            for (let tokenId of tokenIds) {
                                await this.vaultRegistry
                                    .connect(erc20RootVaultSigner)
                                    .approve(this.strategy.address, tokenId);
                            }
                        }
                    );
                };

                this.voltzVaultNfts = voltzVaultNfts;

                return this.strategy;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
        await this.grantPermissionsVoltzVaults();

        const erc20RootVaultNft = await this.erc20RootVault.nft();
        const delayedStrategyParams =
            await this.erc20RootVaultGovernance.delayedStrategyParams(
                erc20RootVaultNft
            );

        await this.erc20RootVaultGovernance
            .connect(this.admin)
            .stageDelayedStrategyParams(erc20RootVaultNft, {
                strategyTreasury: delayedStrategyParams.strategyTreasury,
                strategyPerformanceTreasury:
                    delayedStrategyParams.strategyPerformanceTreasury,
                privateVault: false,
                managementFee: 0,
                performanceFee: 0,
                depositCallbackAddress: this.strategy.address,
                withdrawCallbackAddress: this.strategy.address,
            });
        await sleep(86400);
        await this.erc20RootVaultGovernance
            .connect(this.admin)
            .commitDelayedStrategyParams(erc20RootVaultNft);

        await this.usdc
            .connect(this.deployer)
            .approve(this.erc20RootVault.address, BigNumber.from(10).pow(27));
        await this.usdc
            .connect(this.admin)
            .approve(this.erc20RootVault.address, BigNumber.from(10).pow(27));

        //first deposit
        await mint("USDC", this.admin.address, BigNumber.from(10).pow(5));
        await this.erc20RootVault
            .connect(this.admin)
            .deposit(
                [BigNumber.from(10).pow(5)],
                BigNumber.from(0).toString(),
                []
            );

        let randAddr = randomAddress();
        this.user1 = {
            address: randAddr,
            signer: await addSigner(randAddr),
            lpTokens: 0,
        };

        randAddr = randomAddress();
        this.user2 = {
            address: randAddr,
            signer: await addSigner(randAddr),
            lpTokens: 0,
        };

        await this.usdc
            .connect(this.user1.signer)
            .approve(this.erc20RootVault.address, BigNumber.from(10).pow(27));
        await this.usdc
            .connect(this.user2.signer)
            .approve(this.erc20RootVault.address, BigNumber.from(10).pow(27));

        await this.strategy.connect(this.admin).setVaultParams(0, {
            sigmaWad: "100000000000000000",
            maxPossibleLowerBoundWad: "1500000000000000000",
            proximityWad: "100000000000000000",
            weight: "1",
        });

        for (let vault of this.voltzVaults) {
            await withSigner(vault.address, async (signer) => {
                await this.usdc
                    .connect(signer)
                    .approve(
                        this.deployer.address,
                        ethers.constants.MaxUint256
                    );

                await this.usdc
                    .connect(signer)
                    .transfer(
                        this.deployer.address,
                        await this.usdc.balanceOf(vault.address)
                    );
            });
        }

        await this.usdc
            .connect(this.user1.signer)
            .transfer(
                this.admin.address,
                await this.usdc.balanceOf(this.user1.address)
            );
        await this.usdc
            .connect(this.user2.signer)
            .transfer(
                this.admin.address,
                await this.usdc.balanceOf(this.user2.address)
            );

        const voltzVaultOwnerAddress = await this.vaultRegistry.ownerOf(
            this.voltzVaultNfts[0]
        );
        this.voltzVaultOwner = await addSigner(voltzVaultOwnerAddress);
    });

    it("e2e #1: User 1 deposits, Swap, User 2 deposits", async () => {
        expect(await this.usdc.balanceOf(this.user1.address)).to.be.eq(0);
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.eq(0);

        await mint(
            "USDC",
            this.user1.address,
            BigNumber.from(10).pow(6).mul(100000)
        );
        await this.preparePush();
        await this.erc20RootVault
            .connect(this.user1.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(100000)],
                BigNumber.from(0).toString(),
                []
            );

        this.user1.lpTokens = await this.erc20RootVault.balanceOf(
            this.user1.address
        );

        // trade VT with some other account
        const { test } = await getNamedAccounts();
        const testSigner = await hre.ethers.getSigner(test);
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(1000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: false,
            notional: BigNumber.from(10).pow(6).mul(1000000),
            sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(1000000),
        });

        // advance time by 20 days
        await network.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();

        await mint(
            "USDC",
            this.user2.address,
            BigNumber.from(10).pow(6).mul(1000)
        );
        await this.erc20RootVault
            .connect(this.user2.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(1000)],
                BigNumber.from(0),
                []
            );
        this.user2.lpTokens = await this.erc20RootVault.balanceOf(
            this.user2.address
        );

        // advance time by 60 days to reach maturity
        await network.provider.send("evm_increaseTime", [60 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();
        await this.voltzVaults[0].settleVault(0);

        await this.erc20RootVault
            .connect(this.user1.signer)
            .withdraw(
                this.user1.address,
                this.user1.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        await this.erc20RootVault
            .connect(this.user2.signer)
            .withdraw(
                this.user2.address,
                this.user2.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        expect(await this.usdc.balanceOf(this.user1.address)).to.be.closeTo(
            BigNumber.from(100059531613),
            1000
        );
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.closeTo(
            BigNumber.from(1000001404),
            1000
        );
    });

    it("e2e #2: User 1 deposits, Swap, User 2 deposits, Swap", async () => {
        expect(await this.usdc.balanceOf(this.user1.address)).to.be.eq(0);
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.eq(0);

        await mint(
            "USDC",
            this.user1.address,
            BigNumber.from(10).pow(6).mul(100000)
        );
        await this.preparePush();
        await this.erc20RootVault
            .connect(this.user1.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(100000)],
                BigNumber.from(0).toString(),
                []
            );
        this.user1.lpTokens = await this.erc20RootVault.balanceOf(
            this.user1.address
        );

        // trade VT with some other account
        const { test } = await getNamedAccounts();
        const testSigner = await hre.ethers.getSigner(test);
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(100000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: false,
            notional: BigNumber.from(10).pow(6).mul(100000000),
            sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(100000000),
        });

        // advance time by 20 days
        await network.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();

        await mint(
            "USDC",
            this.user2.address,
            BigNumber.from(10).pow(6).mul(1000)
        );
        await this.erc20RootVault
            .connect(this.user2.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(1000)],
                BigNumber.from(0),
                []
            );
        this.user2.lpTokens = await this.erc20RootVault.balanceOf(
            this.user2.address
        );

        // trade FT
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(100000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: true,
            notional: BigNumber.from(10).pow(6).mul(100000000),
            sqrtPriceLimitX96: MAX_SQRT_RATIO.sub(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(100000000),
        });

        // advance time by 60 days to reach maturity
        await network.provider.send("evm_increaseTime", [60 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();
        await this.voltzVaults[0].settleVault(0);

        await this.erc20RootVault
            .connect(this.user1.signer)
            .withdraw(
                this.user1.address,
                this.user1.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        await this.erc20RootVault
            .connect(this.user2.signer)
            .withdraw(
                this.user2.address,
                this.user2.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        expect(await this.usdc.balanceOf(this.user1.address)).to.be.closeTo(
            BigNumber.from(100062735231),
            1000
        );
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.closeTo(
            BigNumber.from(1000033421),
            1000
        );
    });

    it("e2e #3: User 1 deposits, Change Leverage, User 2 deposits", async () => {
        expect(await this.usdc.balanceOf(this.user1.address)).to.be.eq(0);
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.eq(0);

        await mint(
            "USDC",
            this.user1.address,
            BigNumber.from(10).pow(6).mul(100000)
        );
        await this.preparePush();
        await this.erc20RootVault
            .connect(this.user1.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(100000)],
                BigNumber.from(0).toString(),
                []
            );
        this.user1.lpTokens = await this.erc20RootVault.balanceOf(
            this.user1.address
        );

        await this.voltzVaults[0].connect(this.admin).setLeverageWad(
            BigNumber.from(10)
                .pow(18)
                .mul(leverage * 10)
        );
        let currentPosition = await this.voltzVaults[0].currentPosition();
        await this.voltzVaults[0].connect(this.admin).rebalance({
            tickLower: currentPosition.tickLower,
            tickUpper: currentPosition.tickUpper,
        });

        // advance time by 20 days
        await network.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();

        await mint(
            "USDC",
            this.user2.address,
            BigNumber.from(10).pow(6).mul(1000)
        );
        await this.erc20RootVault
            .connect(this.user2.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(1000)],
                BigNumber.from(0),
                []
            );
        this.user2.lpTokens = await this.erc20RootVault.balanceOf(
            this.user2.address
        );

        // advance time by 60 days to reach maturity
        await network.provider.send("evm_increaseTime", [60 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();
        await this.voltzVaults[0].settleVault(0);

        await this.erc20RootVault
            .connect(this.user1.signer)
            .withdraw(
                this.user1.address,
                this.user1.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        await this.erc20RootVault
            .connect(this.user2.signer)
            .withdraw(
                this.user2.address,
                this.user2.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        expect(await this.usdc.balanceOf(this.user1.address)).to.be.closeTo(
            BigNumber.from(10).pow(6).mul(100000),
            0
        );
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.closeTo(
            BigNumber.from(10).pow(6).mul(1000),
            0
        );
    });

    it("e2e #4: User 1 deposits, Swap SPL, Change Leverage, User 2 deposits", async () => {
        expect(await this.usdc.balanceOf(this.user1.address)).to.be.eq(0);
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.eq(0);

        await mint(
            "USDC",
            this.user1.address,
            BigNumber.from(10).pow(6).mul(100000)
        );
        await this.preparePush();
        await this.erc20RootVault
            .connect(this.user1.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(100000)],
                BigNumber.from(0).toString(),
                []
            );
        this.user1.lpTokens = await this.erc20RootVault.balanceOf(
            this.user1.address
        );

        // trade VT with some other account
        const { test } = await getNamedAccounts();
        const testSigner = await hre.ethers.getSigner(test);
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(100000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: false,
            notional: BigNumber.from(10).pow(6).mul(100000000),
            sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(100000000),
        });

        // change leverage
        await this.voltzVaults[0].connect(this.strategySigner).setLeverageWad(
            BigNumber.from(10)
                .pow(18)
                .mul(leverage * 10)
        );
        let currentPosition = await this.voltzVaults[0].currentPosition();
        await this.voltzVaults[0].connect(this.strategySigner).rebalance({
            tickLower: currentPosition.tickLower,
            tickUpper: currentPosition.tickUpper,
        });

        // advance time by 20 days
        await network.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();

        await mint(
            "USDC",
            this.user2.address,
            BigNumber.from(10).pow(6).mul(1000)
        );
        await this.erc20RootVault
            .connect(this.user2.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(1000)],
                BigNumber.from(0),
                []
            );
        this.user2.lpTokens = await this.erc20RootVault.balanceOf(
            this.user2.address
        );

        // advance time by 60 days to reach maturity
        await network.provider.send("evm_increaseTime", [60 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();
        await this.voltzVaults[0].settleVault(0);

        await this.erc20RootVault
            .connect(this.user1.signer)
            .withdraw(
                this.user1.address,
                this.user1.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        await this.erc20RootVault
            .connect(this.user2.signer)
            .withdraw(
                this.user2.address,
                this.user2.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        expect(await this.usdc.balanceOf(this.user1.address)).to.be.closeTo(
            BigNumber.from(100059531613),
            1000
        );
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.closeTo(
            BigNumber.from(1000001404),
            1000
        );
    });

    it("e2e #5: User 1 deposits, Swap, Change Leverage, User 2 deposits", async () => {
        expect(await this.usdc.balanceOf(this.user1.address)).to.be.eq(0);
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.eq(0);

        await mint(
            "USDC",
            this.user1.address,
            BigNumber.from(10).pow(6).mul(100000)
        );
        await this.preparePush();
        await this.erc20RootVault
            .connect(this.user1.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(100000)],
                BigNumber.from(0).toString(),
                []
            );
        this.user1.lpTokens = await this.erc20RootVault.balanceOf(
            this.user1.address
        );

        // trade VT with some other account
        const { test } = await getNamedAccounts();
        const testSigner = await hre.ethers.getSigner(test);
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(1000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: false,
            notional: BigNumber.from(10).pow(6).mul(1000000),
            sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(1000000),
        });

        // change leverage
        await this.voltzVaults[0].connect(this.admin).setLeverageWad(
            BigNumber.from(10)
                .pow(18)
                .mul(leverage * 10)
        );
        let currentPosition = await this.voltzVaults[0].currentPosition();
        await this.voltzVaults[0].connect(this.admin).rebalance({
            tickLower: currentPosition.tickLower,
            tickUpper: currentPosition.tickUpper,
        });

        // advance time by 20 days
        await network.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();

        await mint(
            "USDC",
            this.user2.address,
            BigNumber.from(10).pow(6).mul(1000)
        );
        await this.erc20RootVault
            .connect(this.user2.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(1000)],
                BigNumber.from(0),
                []
            );
        this.user2.lpTokens = await this.erc20RootVault.balanceOf(
            this.user2.address
        );

        // advance time by 60 days to reach maturity
        await network.provider.send("evm_increaseTime", [60 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();
        await this.voltzVaults[0].settleVault(0);

        await this.erc20RootVault
            .connect(this.user1.signer)
            .withdraw(
                this.user1.address,
                this.user1.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        await this.erc20RootVault
            .connect(this.user2.signer)
            .withdraw(
                this.user2.address,
                this.user2.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        expect(await this.usdc.balanceOf(this.user1.address)).to.be.closeTo(
            BigNumber.from(99987062685),
            1000
        );
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.closeTo(
            BigNumber.from(999999999),
            1000
        );
    });

    it("e2e #6: User 1 deposits, Swap, Change Leverage, User 2 deposits, Swap", async () => {
        expect(await this.usdc.balanceOf(this.user1.address)).to.be.eq(0);
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.eq(0);

        await mint(
            "USDC",
            this.user1.address,
            BigNumber.from(10).pow(6).mul(100000)
        );
        await this.preparePush();
        await this.erc20RootVault
            .connect(this.user1.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(100000)],
                BigNumber.from(0).toString(),
                []
            );
        this.user1.lpTokens = await this.erc20RootVault.balanceOf(
            this.user1.address
        );

        // trade VT with some other account
        const { test } = await getNamedAccounts();
        const testSigner = await hre.ethers.getSigner(test);
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(1000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: false,
            notional: BigNumber.from(10).pow(6).mul(1000000),
            sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(1000000),
        });

        // change leverage
        await this.voltzVaults[0].connect(this.strategySigner).setLeverageWad(
            BigNumber.from(10)
                .pow(18)
                .mul(leverage * 10)
        );
        let currentPosition = await this.voltzVaults[0].currentPosition();
        await this.voltzVaults[0].connect(this.strategySigner).rebalance({
            tickLower: currentPosition.tickLower,
            tickUpper: currentPosition.tickUpper,
        });

        // advance time by 20 days
        await network.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();

        await mint(
            "USDC",
            this.user2.address,
            BigNumber.from(10).pow(6).mul(1000)
        );
        await this.erc20RootVault
            .connect(this.user2.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(1000)],
                BigNumber.from(0),
                []
            );
        this.user2.lpTokens = await this.erc20RootVault.balanceOf(
            this.user2.address
        );

        // trade FT
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(100000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: true,
            notional: BigNumber.from(10).pow(6).mul(100000000),
            sqrtPriceLimitX96: MAX_SQRT_RATIO.sub(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(100000000),
        });

        // advance time by 60 days to reach maturity
        await network.provider.send("evm_increaseTime", [60 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        await this.voltzVaults[0].updateTvl();
        await this.voltzVaults[0].settleVault(0);

        await this.erc20RootVault
            .connect(this.user1.signer)
            .withdraw(
                this.user1.address,
                this.user1.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        await this.erc20RootVault
            .connect(this.user2.signer)
            .withdraw(
                this.user2.address,
                this.user2.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        expect(await this.usdc.balanceOf(this.user1.address)).to.be.closeTo(
            BigNumber.from(100019094304),
            1000
        );
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.closeTo(
            BigNumber.from(1000320357),
            1000
        );
    });

    it("e2e #7: User 1 deposits, Swap, Change Leverage, User 2 deposits, Swap -- 2 pools", async () => {
        expect(await this.usdc.balanceOf(this.user1.address)).to.be.eq(0);
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.eq(0);

        await mint(
            "USDC",
            this.user1.address,
            BigNumber.from(10).pow(6).mul(100000)
        );
        await this.preparePush();
        await this.erc20RootVault
            .connect(this.user1.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(100000)],
                BigNumber.from(0).toString(),
                []
            );
        this.user1.lpTokens = await this.erc20RootVault.balanceOf(
            this.user1.address
        );

        // trade VT with some other account
        const { test } = await getNamedAccounts();
        const testSigner = await hre.ethers.getSigner(test);
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(1000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: false,
            notional: BigNumber.from(10).pow(6).mul(1000000),
            sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(1000000),
        });

        // change leverage of all vaults
        for (let vault of this.voltzVaults) {
            await vault.connect(this.strategySigner).setLeverageWad(
                BigNumber.from(10)
                    .pow(18)
                    .mul(leverage * 10)
            );
        }

        for (let vault of this.voltzVaults) {
            let currentPosition = await vault.currentPosition();
            await vault.connect(this.strategySigner).rebalance({
                tickLower: currentPosition.tickLower,
                tickUpper: currentPosition.tickUpper,
            });
        }

        // advance time by 20 days
        await network.provider.send("evm_increaseTime", [20 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        for (let vault of this.voltzVaults) {
            await vault.updateTvl();
        }

        await mint(
            "USDC",
            this.user2.address,
            BigNumber.from(10).pow(6).mul(1000)
        );
        await this.erc20RootVault
            .connect(this.user2.signer)
            .deposit(
                [BigNumber.from(10).pow(6).mul(1000)],
                BigNumber.from(0),
                []
            );
        this.user2.lpTokens = await this.erc20RootVault.balanceOf(
            this.user2.address
        );

        // trade FT
        await mint(
            "USDC",
            testSigner.address,
            BigNumber.from(10).pow(6).mul(100000000)
        );
        await this.usdc
            .connect(testSigner)
            .approve(this.periphery, BigNumber.from(10).pow(27));
        await this.peripheryContract.connect(testSigner).swap({
            marginEngine: this.marginEngine,
            isFT: true,
            notional: BigNumber.from(10).pow(6).mul(100000000),
            sqrtPriceLimitX96: MAX_SQRT_RATIO.sub(1),
            tickLower: -60,
            tickUpper: 60,
            marginDelta: BigNumber.from(10).pow(6).mul(100000000),
        });

        // advance time by 60 days to reach maturity
        await network.provider.send("evm_increaseTime", [60 * 24 * 60 * 60]);
        await network.provider.send("evm_mine", []);

        for (let vault of this.voltzVaults) {
            await vault.updateTvl();
            await vault.settleVault(0);
        }

        await this.erc20RootVault
            .connect(this.user1.signer)
            .withdraw(
                this.user1.address,
                this.user1.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        await this.erc20RootVault
            .connect(this.user2.signer)
            .withdraw(
                this.user2.address,
                this.user2.lpTokens,
                [0],
                vaultWithdrawalOptions
            );

        expect(await this.usdc.balanceOf(this.user1.address)).to.be.closeTo(
            BigNumber.from(100019094304),
            1000
        );
        expect(await this.usdc.balanceOf(this.user2.address)).to.be.closeTo(
            BigNumber.from(1000320357),
            1000
        );
    });
});
