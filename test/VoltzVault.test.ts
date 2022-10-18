import hre, { network } from "hardhat";
import { utils } from "ethers";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    mintUSDCForVoltz,
    randomAddress,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20RootVault,
    ERC20Vault,
    IMarginEngine,
    IPeriphery,
    IRateOracle,
    IVAMM,
    VoltzVault,
} from "./types";
import { combineVaults, setupVault } from "../deploy/0000_utils";
import { VOLTZ_VAULT_INTERFACE_ID } from "./library/Constants";
import { TickMath } from "@uniswap/v3-sdk";
import { TickRangeStruct } from "./types/IVoltzVault";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    marginEngine: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<VoltzVault, DeployOptions, CustomContext>("VoltzVault", function () {
    this.timeout(200000);
    const leverage = 10;
    const marginMultiplierPostUnwind = 2;
    const lookbackWindow = 1209600; // 14 days
    const estimatedAPYDecimalDelta = 0;

    const MIN_SQRT_RATIO = BigNumber.from("2503036416286949174936592462");
    const MAX_SQRT_RATIO = BigNumber.from("2507794810551837817144115957740");

    const YEAR_IN_SECONDS = 31536000;

    const getTrackedPositions = async () => {
        let err = undefined;
        let trackedPositions = [];
        while (err === undefined) {
            try {
                const trackedPosition: TickRangeStruct =
                    await this.subject.trackedPositions(
                        trackedPositions.length
                    );
                trackedPositions.push(trackedPosition);
            } catch (e) {
                err = e as Error;
            }
        }

        return trackedPositions;
    };

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

                    await mintUSDCForVoltz(
                        BigNumber.from(10).pow(6).mul(10000)
                    );
                };

                const tokens = [this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let voltzVaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                const currentTick = (await this.vammContract.vammVars()).tick;
                this.initialTickLow = currentTick - (currentTick % 60) - 600;
                this.initialTickHigh = currentTick - (currentTick % 60) + 600;

                this.voltzVaultHelperSingleton = (
                    await ethers.getContract("VoltzVaultHelper")
                ).address;

                await setupVault(hre, voltzVaultNft, "VoltzVaultGovernance", {
                    createVaultArgs: [
                        tokens,
                        this.deployer.address,
                        marginEngine,
                        this.voltzVaultHelperSingleton,
                        {
                            tickLower: this.initialTickLow,
                            tickUpper: this.initialTickHigh,
                            leverageWad: utils.parseEther(leverage.toString()),
                            marginMultiplierPostUnwindWad: utils.parseEther(
                                marginMultiplierPostUnwind.toString()
                            ),
                            lookbackWindowInSeconds: lookbackWindow,
                            estimatedAPYDecimalDeltaWad: utils.parseEther(
                                estimatedAPYDecimalDelta.toString()
                            ),
                        },
                    ],
                });

                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, voltzVaultNft],
                    this.deployer.address,
                    this.deployer.address
                );

                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );

                const voltzVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    voltzVaultNft
                );
                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.subject = await ethers.getContractAt(
                    "VoltzVault",
                    voltzVault
                );

                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );

                this.voltzVaultHelperContract = await ethers.getContractAt(
                    "VoltzVaultHelper",
                    await this.subject.voltzVaultHelper()
                );

                for (let address of [
                    this.deployer.address,
                    this.subject.address,
                    this.erc20Vault.address,
                ]) {
                    await mint(
                        "USDC",
                        address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
                    await this.usdc.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                }

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("Test Deposit (Push)", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
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
                        await this.usdc.balanceOf(this.subject.address)
                    );
            });
        });

        it("push #1: check position margin and leverage", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );

            const ticks = await this.subject.currentPosition();
            const currentVoltzPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    ticks.tickLower,
                    ticks.tickUpper
                );

            expect(currentVoltzPositionInfo.margin).to.be.equal(
                BigNumber.from(10).pow(6).mul(1000)
            );

            const sqrtPriceLower = BigNumber.from(
                TickMath.getSqrtRatioAtTick(ticks.tickLower).toString()
            );
            const sqrtPriceUpper = BigNumber.from(
                TickMath.getSqrtRatioAtTick(ticks.tickUpper).toString()
            );
            const liquidityNotional = currentVoltzPositionInfo._liquidity
                .mul(sqrtPriceUpper.sub(sqrtPriceLower))
                .div(BigNumber.from(2).pow(96));

            expect(liquidityNotional).to.be.closeTo(
                BigNumber.from(10).pow(6).mul(1000).mul(leverage),
                BigNumber.from(10)
                    .pow(6)
                    .mul(1000)
                    .mul(leverage)
                    .div(1000)
                    .toNumber()
            );
        });

        it("push #1: after maturity", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            // advance time by 60 days to reach maturity
            await network.provider.send("evm_increaseTime", [
                60 * 24 * 60 * 60,
            ]);
            await network.provider.send("evm_mine", []);

            await this.preparePush();
            await expect(
                this.subject.push(
                    [this.usdc.address],
                    [BigNumber.from(10).pow(6).mul(1000)],
                    encodeToBytes([], [])
                )
            ).to.be.revertedWith("closeToOrBeyondMaturity");
        });
    });

    describe("Initialisation, Getters, Setters", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
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
                        await this.usdc.balanceOf(this.subject.address)
                    );
            });
        });

        it("check vault can be initialised only once", async () => {
            const tokens = [this.usdc.address]
                .map((t) => t.toLowerCase())
                .sort();

            await expect(
                this.subject.initialize(
                    0x01,
                    tokens,
                    this.marginEngine,
                    this.periphery,
                    this.voltzVaultHelperSingleton,
                    {
                        tickLower: this.initialTickLow,
                        tickUpper: this.initialTickHigh,
                        leverageWad: utils.parseEther(leverage.toString()),
                        marginMultiplierPostUnwindWad: utils.parseEther(
                            marginMultiplierPostUnwind.toString()
                        ),
                        lookbackWindowInSeconds: lookbackWindow,
                        estimatedAPYDecimalDeltaWad: utils.parseEther(
                            estimatedAPYDecimalDelta.toString()
                        ),
                    }
                )
            ).to.be.revertedWith("INIT");
        });

        it("check helper can be initialised only once", async () => {
            await expect(
                this.voltzVaultHelperContract.initialize()
            ).to.be.revertedWith("INIT");
        });

        it("check current position getter", async () => {
            const initialPosition = await this.subject.currentPosition();

            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );
            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );

            expect(await this.subject.currentPosition()).to.deep.equal(
                initialPosition
            );

            let newPosition = {
                tickLower: -60,
                tickUpper: 60,
            };
            await this.subject.rebalance(newPosition);
            expect(await this.subject.currentPosition()).to.deep.equal([
                newPosition.tickLower,
                newPosition.tickUpper,
            ]);
        });

        it("check vault params getters & setters", async () => {
            // check init params
            expect(await this.subject.leverageWad()).to.be.equal(
                utils.parseEther(leverage.toString())
            );
            expect(
                await this.subject.marginMultiplierPostUnwindWad()
            ).to.be.equal(
                utils.parseEther(marginMultiplierPostUnwind.toString())
            );
            expect(await this.subject.lookbackWindow()).to.be.equal(
                lookbackWindow.toString()
            );
            expect(
                await this.subject.estimatedAPYDecimalDeltaWad()
            ).to.be.equal(
                utils.parseEther(estimatedAPYDecimalDelta.toString())
            );

            const { test } = await getNamedAccounts();
            const testSigner = await hre.ethers.getSigner(test);

            // check someone else cannot set params
            await expect(
                this.subject.connect(testSigner).setLeverageWad(leverage + 1)
            ).to.be.revertedWith("FRB");
            await expect(
                this.subject
                    .connect(testSigner)
                    .setMarginMultiplierPostUnwindWad(
                        marginMultiplierPostUnwind + 1
                    )
            ).to.be.revertedWith("FRB");
            await expect(
                this.subject
                    .connect(testSigner)
                    .setLookbackWindow(lookbackWindow + 1)
            ).to.be.revertedWith("FRB");
            await expect(
                this.subject
                    .connect(testSigner)
                    .setEstimatedAPYDecimalDeltaWad(
                        estimatedAPYDecimalDelta + 1
                    )
            ).to.be.revertedWith("FRB");

            // check someone else can see params
            expect(
                await this.subject.connect(testSigner).leverageWad()
            ).to.be.equal(utils.parseEther(leverage.toString()));
            expect(
                await this.subject
                    .connect(testSigner)
                    .marginMultiplierPostUnwindWad()
            ).to.be.equal(
                utils.parseEther(marginMultiplierPostUnwind.toString())
            );
            expect(
                await this.subject.connect(testSigner).lookbackWindow()
            ).to.be.equal(lookbackWindow.toString());
            expect(
                await this.subject
                    .connect(testSigner)
                    .estimatedAPYDecimalDeltaWad()
            ).to.be.equal(
                utils.parseEther(estimatedAPYDecimalDelta.toString())
            );

            // check we can re-set params
            await this.subject.setLeverageWad(
                utils.parseEther((leverage + 1).toString())
            );
            await this.subject.setMarginMultiplierPostUnwindWad(
                utils.parseEther((marginMultiplierPostUnwind + 1).toString())
            );
            await this.subject.setLookbackWindow(lookbackWindow + 1);
            await this.subject.setEstimatedAPYDecimalDeltaWad(
                utils.parseEther((estimatedAPYDecimalDelta + 1).toString())
            );

            // check re-set params
            expect(await this.subject.leverageWad()).to.be.equal(
                utils.parseEther((leverage + 1).toString())
            );
            expect(
                await this.subject.marginMultiplierPostUnwindWad()
            ).to.be.equal(
                utils.parseEther((marginMultiplierPostUnwind + 1).toString())
            );
            expect(await this.subject.lookbackWindow()).to.be.equal(
                (lookbackWindow + 1).toString()
            );
            expect(
                await this.subject.estimatedAPYDecimalDeltaWad()
            ).to.be.equal(
                utils.parseEther((estimatedAPYDecimalDelta + 1).toString())
            );
        });

        it("check helper params getters & setters", async () => {
            // check init params
            expect(
                await this.voltzVaultHelperContract.marginMultiplierPostUnwindWad()
            ).to.be.equal(
                utils.parseEther(marginMultiplierPostUnwind.toString())
            );
            expect(
                await this.voltzVaultHelperContract.lookbackWindow()
            ).to.be.equal(lookbackWindow.toString());
            expect(
                await this.voltzVaultHelperContract.estimatedAPYDecimalDeltaWad()
            ).to.be.equal(
                utils.parseEther(estimatedAPYDecimalDelta.toString())
            );

            const { test } = await getNamedAccounts();
            const testSigner = await hre.ethers.getSigner(test);

            // check someone else cannot set params
            await expect(
                this.voltzVaultHelperContract
                    .connect(testSigner)
                    .setMarginMultiplierPostUnwindWad(
                        marginMultiplierPostUnwind + 1
                    )
            ).to.be.revertedWith("Only Vault");
            await expect(
                this.voltzVaultHelperContract
                    .connect(testSigner)
                    .setLookbackWindow(lookbackWindow + 1)
            ).to.be.revertedWith("Only Vault");
            await expect(
                this.voltzVaultHelperContract
                    .connect(testSigner)
                    .setEstimatedAPYDecimalDeltaWad(
                        estimatedAPYDecimalDelta + 1
                    )
            ).to.be.revertedWith("Only Vault");

            // check we cannot re-set params
            await expect(
                this.voltzVaultHelperContract.setMarginMultiplierPostUnwindWad(
                    marginMultiplierPostUnwind + 1
                )
            ).to.be.revertedWith("Only Vault");
            await expect(
                this.voltzVaultHelperContract.setLookbackWindow(
                    lookbackWindow + 1
                )
            ).to.be.revertedWith("Only Vault");
            await expect(
                this.voltzVaultHelperContract.setEstimatedAPYDecimalDeltaWad(
                    estimatedAPYDecimalDelta + 1
                )
            ).to.be.revertedWith("Only Vault");

            // check vault can update helper params
            await this.subject.setMarginMultiplierPostUnwindWad(
                utils.parseEther((marginMultiplierPostUnwind + 1).toString())
            );
            expect(
                await this.voltzVaultHelperContract.marginMultiplierPostUnwindWad()
            ).to.be.equal(
                utils.parseEther((marginMultiplierPostUnwind + 1).toString())
            );
            await this.subject.setLookbackWindow(lookbackWindow + 1);
            expect(
                await this.voltzVaultHelperContract.lookbackWindow()
            ).to.be.equal((lookbackWindow + 1).toString());
            await this.subject.setEstimatedAPYDecimalDeltaWad(
                utils.parseEther((estimatedAPYDecimalDelta + 1).toString())
            );
            expect(
                await this.voltzVaultHelperContract.estimatedAPYDecimalDeltaWad()
            ).to.be.equal(
                utils.parseEther((estimatedAPYDecimalDelta + 1).toString())
            );
        });

        it("check vault & helper pool info getters", async () => {
            expect(await this.subject.marginEngine()).to.be.equal(
                this.marginEngine
            );
            expect(await this.subject.rateOracle()).to.be.equal(
                this.rateOracle
            );
            expect(await this.subject.periphery()).to.be.equal(this.periphery);
            expect(await this.subject.vamm()).to.be.equal(this.vamm);

            expect(await this.voltzVaultHelperContract.callStatic.vault()).to.be.equal(this.subject.address);
        });
    });

    describe("Test Withdraw (Pull)", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
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
                        await this.usdc.balanceOf(this.subject.address)
                    );
            });
        });

        it("pull #1", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );

            expect(await this.usdc.balanceOf(this.subject.address)).to.be.equal(
                BigNumber.from(0)
            );

            {
                await expect(
                    this.subject.callStatic.pull(
                        this.erc20Vault.address,
                        [this.usdc.address],
                        [BigNumber.from(10).pow(6).mul(1000)],
                        encodeToBytes([], [])
                    )
                ).to.be.revertedWith("FRB");
            }

            // advance time by 60 days to reach maturity
            await network.provider.send("evm_increaseTime", [
                60 * 24 * 60 * 60,
            ]);
            await network.provider.send("evm_mine", []);

            await this.subject.settleVault(0);

            {
                const actualTokenAmounts = await this.subject.callStatic.pull(
                    this.erc20Vault.address,
                    [this.usdc.address],
                    [BigNumber.from(10).pow(6).mul(1000)],
                    encodeToBytes([], [])
                );
                expect(actualTokenAmounts[0]).to.be.equal(
                    BigNumber.from(10).pow(6).mul(1000)
                );
            }

            const erc20VaultFundsBeforePull = await this.usdc.balanceOf(
                this.erc20Vault.address
            );

            await this.subject.pull(
                this.erc20Vault.address,
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );
            const erc20VaultFundsAfterPull = await this.usdc.balanceOf(
                this.erc20Vault.address
            );
            expect(
                erc20VaultFundsAfterPull.sub(erc20VaultFundsBeforePull)
            ).to.be.equal(BigNumber.from(10).pow(6).mul(1000));
        });
    });

    describe("Test Rebalance", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
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
                        await this.usdc.balanceOf(this.subject.address)
                    );
            });
        });

        it("rebalance #1: vt = 0", async () => {
            // Push 1000
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );

            // trade VT with some other account
            const { test } = await getNamedAccounts();
            const testSigner = await hre.ethers.getSigner(test);

            await mint(
                "USDC",
                testSigner.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.usdc
                .connect(testSigner)
                .approve(this.periphery, BigNumber.from(10).pow(27));

            await this.peripheryContract.connect(testSigner).swap({
                marginEngine: this.marginEngine,
                isFT: false,
                notional: BigNumber.from(10).pow(6).mul(1000),
                sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
                tickLower: -60,
                tickUpper: 60,
                marginDelta: BigNumber.from(10).pow(6).mul(1000),
            });

            // rebalance to some new position
            const newPosition = {
                tickLower: -60,
                tickUpper: 60,
            };
            await this.subject.rebalance(newPosition);

            // must check the following on the previous position
            // liquidity = 0
            // vt = 0
            // margin left in position is margin requirement + 1
            const lpInitialPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh
                );

            expect(lpInitialPositionInfo._liquidity).to.be.equal(
                BigNumber.from(0)
            );
            expect(lpInitialPositionInfo.variableTokenBalance).to.be.equal(
                BigNumber.from(0)
            );

            const positionRequirementInitial =
                await this.marginEngineContract.callStatic.getPositionMarginRequirement(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh,
                    false
                );

            expect(lpInitialPositionInfo.margin).to.be.equal(
                positionRequirementInitial.add(BigNumber.from(1))
            );

            // must check the following on the new position
            // margin is 1000 - lpInitialPositionInfo.margin - fees
            const lpNewPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    newPosition.tickLower,
                    newPosition.tickUpper
                );
            const fees = BigNumber.from(1);
            expect(lpNewPositionInfo.margin).to.be.equal(
                BigNumber.from(10)
                    .pow(6)
                    .mul(1000)
                    .sub(lpInitialPositionInfo.margin.add(fees))
            );
        });

        it("rebalance #2: vt = 0", async () => {
            // Push 1000
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000000000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000000000)],
                encodeToBytes([], [])
            );

            // trade VT with some other account
            const { test } = await getNamedAccounts();
            const testSigner = await hre.ethers.getSigner(test);

            await mint(
                "USDC",
                testSigner.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.usdc
                .connect(testSigner)
                .approve(this.periphery, BigNumber.from(10).pow(27));

            await this.peripheryContract.connect(testSigner).swap({
                marginEngine: this.marginEngine,
                isFT: false,
                notional: BigNumber.from(10).pow(6).mul(1000),
                sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
                tickLower: -60,
                tickUpper: 60,
                marginDelta: BigNumber.from(10).pow(6).mul(1000),
            });

            // rebalance to some new position
            const newPosition = {
                tickLower: -60,
                tickUpper: 60,
            };
            await this.subject.rebalance(newPosition);

            // must check the following on the previous position
            // liquidity = 0
            // vt = 0
            // margin left in position is margin requirement + 1
            const lpInitialPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh
                );

            expect(lpInitialPositionInfo._liquidity).to.be.equal(
                BigNumber.from(0)
            );
            expect(lpInitialPositionInfo.variableTokenBalance).to.be.equal(
                BigNumber.from(0)
            );

            const positionRequirementInitial =
                await this.marginEngineContract.callStatic.getPositionMarginRequirement(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh,
                    false
                );

            expect(lpInitialPositionInfo.margin).to.be.equal(
                positionRequirementInitial.add(BigNumber.from(1))
            );

            // must check the following on the new position
            // margin is 1000 - lpInitialPositionInfo.margin - fees
            const lpNewPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    newPosition.tickLower,
                    newPosition.tickUpper
                );
            const feesLower = BigNumber.from(1);
            const feesUpper = BigNumber.from(2);
            expect(lpNewPositionInfo.margin).to.be.lte(
                BigNumber.from(10)
                    .pow(6)
                    .mul(1000000000)
                    .sub(lpInitialPositionInfo.margin.add(feesLower))
            );
            expect(lpNewPositionInfo.margin).to.be.gte(
                BigNumber.from(10)
                    .pow(6)
                    .mul(1000000000)
                    .sub(lpInitialPositionInfo.margin.add(feesUpper))
            );
        });

        it("rebalance #3: vt < 0, all money blocked", async () => {
            // Push 1000
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000000000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000000000)],
                encodeToBytes([], [])
            );

            // trade VT with some other account
            const { test } = await getNamedAccounts();
            const testSigner = await hre.ethers.getSigner(test);

            await mint(
                "USDC",
                testSigner.address,
                BigNumber.from(10).pow(6).mul(1000000000)
            );

            await this.usdc
                .connect(testSigner)
                .approve(this.periphery, BigNumber.from(10).pow(27));

            await this.peripheryContract.connect(testSigner).swap({
                marginEngine: this.marginEngine,
                isFT: false,
                notional: BigNumber.from(10).pow(6).mul(1000000000),
                sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
                tickLower: -60,
                tickUpper: 60,
                marginDelta: BigNumber.from(10).pow(6).mul(1000000000),
            });

            const lpInitialPositionInfoBeforeRebalance =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh
                );

            // rebalance to some new position
            const newPosition = {
                tickLower: -60,
                tickUpper: 60,
            };
            await this.subject.rebalance(newPosition);

            // must check the following on the previous position
            // liquidity = 0
            // margin left in position stayed the same
            const lpInitialPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh
                );

            expect(lpInitialPositionInfo._liquidity).to.be.equal(
                BigNumber.from(0)
            );

            const positionRequirementInitial =
                await this.marginEngineContract.callStatic.getPositionMarginRequirement(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh,
                    false
                );

            expect(lpInitialPositionInfo.margin).to.be.gt(
                lpInitialPositionInfoBeforeRebalance.margin.mul(999).div(1000)
            );

            // must check the following on the new position
            // margin is 0
            const lpNewPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    newPosition.tickLower,
                    newPosition.tickUpper
                );
            expect(lpNewPositionInfo.margin).to.be.equal(BigNumber.from(0));
        });

        it("rebalance #4: vt < 0, leave initial + buffer behind", async () => {
            // Push 1000000000
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000000000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000000000)],
                encodeToBytes([], [])
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

            // rebalance to some new position
            const newPosition = {
                tickLower: -60,
                tickUpper: 60,
            };
            await this.subject.rebalance(newPosition);

            // must check the following on the previous position
            // liquidity = 0
            // margin left in position is k*req
            const lpInitialPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh
                );

            expect(lpInitialPositionInfo._liquidity).to.be.equal(
                BigNumber.from(0)
            );

            const positionRequirementInitial =
                await this.marginEngineContract.callStatic.getPositionMarginRequirement(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh,
                    false
                );

            expect(lpInitialPositionInfo.margin).to.be.equal(
                positionRequirementInitial.mul(marginMultiplierPostUnwind)
            );

            // must check the following on the new position
            // margin is 1000000000 - lpInitialPositionInfo.margin - fees + rewards
            const lpNewPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    newPosition.tickLower,
                    newPosition.tickUpper
                );
            const rewardsFeeLower = BigNumber.from(30000000000);
            const rewardsFeeUpper = BigNumber.from(32000000000);
            expect(lpNewPositionInfo.margin).to.be.gt(
                BigNumber.from(10)
                    .pow(6)
                    .mul(1000000000)
                    .sub(lpInitialPositionInfo.margin.sub(rewardsFeeLower))
            );
            expect(lpNewPositionInfo.margin).to.be.lt(
                BigNumber.from(10)
                    .pow(6)
                    .mul(1000000000)
                    .sub(lpInitialPositionInfo.margin.sub(rewardsFeeUpper))
            );

            // advance time by 60 days to reach maturity
            await network.provider.send("evm_increaseTime", [
                60 * 24 * 60 * 60,
            ]);
            await network.provider.send("evm_mine", []);

            const sumOfMargins = lpInitialPositionInfo.margin.add(
                lpNewPositionInfo.margin
            );

            // pull 0 to triger settle
            await this.subject.settleVault(0);
            await this.subject.pull(
                this.erc20Vault.address,
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(0)],
                encodeToBytes([], [])
            );

            // make sure both positions are settled
            {
                const lpInitialPositionInfo =
                    await this.marginEngineContract.callStatic.getPosition(
                        this.subject.address,
                        this.initialTickLow,
                        this.initialTickHigh
                    );
                expect(lpInitialPositionInfo.isSettled).to.be.equal(true);

                const lpNewPositionInfo =
                    await this.marginEngineContract.callStatic.getPosition(
                        this.subject.address,
                        newPosition.tickLower,
                        newPosition.tickUpper
                    );
                expect(lpNewPositionInfo.isSettled).to.be.equal(true);
            }

            // balance of vault should be the sum of the margins of the two positions
            // plus the cashflow of the first position
            const cashflowFirstPosition = BigNumber.from(19506091355);
            expect(
                await this.usdc.balanceOf(this.subject.address)
            ).to.be.closeTo(
                sumOfMargins.add(cashflowFirstPosition),
                sumOfMargins.add(cashflowFirstPosition).div(1000)
            );
        });

        it("rebalance #5: check leverage", async () => {
            // Push 1000
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );

            {
                const ticks = await this.subject.currentPosition();
                const currentVoltzPositionInfo =
                    await this.marginEngineContract.callStatic.getPosition(
                        this.subject.address,
                        ticks.tickLower,
                        ticks.tickUpper
                    );

                const sqrtPriceLower = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(ticks.tickLower).toString()
                );
                const sqrtPriceUpper = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(ticks.tickUpper).toString()
                );
                const liquidityNotional = currentVoltzPositionInfo._liquidity
                    .mul(sqrtPriceUpper.sub(sqrtPriceLower))
                    .div(BigNumber.from(2).pow(96));

                expect(liquidityNotional).to.be.closeTo(
                    BigNumber.from(10).pow(6).mul(1000).mul(leverage),
                    BigNumber.from(10)
                        .pow(6)
                        .mul(1000)
                        .mul(leverage)
                        .div(1000)
                        .toNumber()
                );
            }

            await this.subject.rebalance({
                tickLower: 60,
                tickUpper: 600,
            });

            {
                const ticks = await this.subject.currentPosition();
                expect(ticks.tickLower).to.be.equal(60);
                expect(ticks.tickUpper).to.be.equal(600);
                const currentVoltzPositionInfo =
                    await this.marginEngineContract.callStatic.getPosition(
                        this.subject.address,
                        ticks.tickLower,
                        ticks.tickUpper
                    );

                const sqrtPriceLower = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(ticks.tickLower).toString()
                );
                const sqrtPriceUpper = BigNumber.from(
                    TickMath.getSqrtRatioAtTick(ticks.tickUpper).toString()
                );
                const liquidityNotional = currentVoltzPositionInfo._liquidity
                    .mul(sqrtPriceUpper.sub(sqrtPriceLower))
                    .div(BigNumber.from(2).pow(96));

                expect(liquidityNotional).to.be.closeTo(
                    BigNumber.from(10).pow(6).mul(1000).mul(leverage),
                    BigNumber.from(10)
                        .pow(6)
                        .mul(1000)
                        .mul(leverage)
                        .div(1000)
                        .toNumber()
                );
            }
        });
    });

    describe("Test TVL", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
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
                        await this.usdc.balanceOf(this.subject.address)
                    );
            });
        });

        it("tvl #1: no funds", async () => {
            await this.subject.updateTvl();
            const result = await this.subject.tvl();
            for (let amountsId = 0; amountsId < 2; ++amountsId) {
                expect(result[amountsId][0]).eq(0);
            }
        });

        it("tvl #2: LP funds but not swaps", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );

            await this.subject.updateTvl();
            const result = await this.subject.tvl();
            for (let amountsId = 0; amountsId < 2; ++amountsId) {
                expect(result[amountsId][0]).eq(
                    BigNumber.from(10).pow(6).mul(1000)
                );
            }
        });

        it("tvl #3: one swap", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000)],
                encodeToBytes([], [])
            );

            // trade VT with some other account
            const { test } = await getNamedAccounts();
            const testSigner = await hre.ethers.getSigner(test);

            await mint(
                "USDC",
                testSigner.address,
                BigNumber.from(10).pow(6).mul(1000)
            );

            await this.usdc
                .connect(testSigner)
                .approve(this.periphery, BigNumber.from(10).pow(27));

            await this.peripheryContract.connect(testSigner).swap({
                marginEngine: this.marginEngine,
                isFT: false,
                notional: BigNumber.from(10).pow(6).mul(1000),
                sqrtPriceLimitX96: MIN_SQRT_RATIO.add(1),
                tickLower: -60,
                tickUpper: 60,
                marginDelta: BigNumber.from(10).pow(6).mul(1000),
            });

            const currentVoltzPositionInfo =
                await this.marginEngineContract.callStatic.getPosition(
                    this.subject.address,
                    this.initialTickLow,
                    this.initialTickHigh
                );

            const termStartTimestamp = Number(
                ethers.utils.formatEther(
                    await this.marginEngineContract.callStatic.termStartTimestampWad()
                )
            );

            const termEndTimestamp = Number(
                ethers.utils.formatEther(
                    await this.marginEngineContract.callStatic.termEndTimestampWad()
                )
            );

            const fixedCashflow =
                (currentVoltzPositionInfo.fixedTokenBalance *
                    0.01 *
                    (termEndTimestamp - termStartTimestamp)) /
                YEAR_IN_SECONDS;

            let currentTimestamp = (
                await hre.ethers.provider.getBlock("latest")
            ).timestamp;

            // advance time and check tvl after each day
            while (currentTimestamp < termEndTimestamp) {
                const apyStartNow = Number(
                    ethers.utils.formatEther(
                        await this.rateOracleContract.callStatic.getApyFromTo(
                            termStartTimestamp,
                            currentTimestamp
                        )
                    )
                );
                const apyHistoricalLookback = Number(
                    ethers.utils.formatEther(
                        await this.rateOracleContract.callStatic.getApyFromTo(
                            currentTimestamp - lookbackWindow,
                            currentTimestamp
                        )
                    )
                );

                const variableCashflowLower =
                    currentVoltzPositionInfo.variableTokenBalance *
                    ((apyStartNow * (currentTimestamp - termStartTimestamp)) /
                        YEAR_IN_SECONDS +
                        (apyHistoricalLookback *
                            (1 - estimatedAPYDecimalDelta) *
                            (termEndTimestamp - currentTimestamp)) /
                            YEAR_IN_SECONDS);

                const variableCashflowUpper =
                    currentVoltzPositionInfo.variableTokenBalance *
                    ((apyStartNow * (currentTimestamp - termStartTimestamp)) /
                        YEAR_IN_SECONDS +
                        (apyHistoricalLookback *
                            (1 + estimatedAPYDecimalDelta) *
                            (termEndTimestamp - currentTimestamp)) /
                            YEAR_IN_SECONDS);

                const groundTruthTvlLower = currentVoltzPositionInfo.margin.add(
                    Math.floor(fixedCashflow + variableCashflowLower)
                );
                const groundTruthTvlUpper = currentVoltzPositionInfo.margin.add(
                    Math.floor(fixedCashflow + variableCashflowUpper)
                );

                await this.subject.updateTvl();
                const tvl = await this.subject.tvl();
                expect(tvl[0][0].toNumber()).to.be.closeTo(
                    groundTruthTvlLower.toNumber(),
                    groundTruthTvlLower.div(1000).toNumber()
                );

                expect(tvl[1][0].toNumber()).to.be.closeTo(
                    groundTruthTvlUpper.toNumber(),
                    groundTruthTvlUpper.div(1000).toNumber()
                );

                // advance time by 1 day
                await network.provider.send("evm_increaseTime", [24 * 60 * 60]);
                await network.provider.send("evm_mine", []);
                currentTimestamp += 24 * 60 * 60;
            }
        });

        it("tvl #4: one rebalance, two swaps", async () => {
            await mint(
                "USDC",
                this.subject.address,
                BigNumber.from(10).pow(6).mul(1000000000)
            );

            await this.preparePush();
            await this.subject.push(
                [this.usdc.address],
                [BigNumber.from(10).pow(6).mul(1000000000)],
                encodeToBytes([], [])
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

            // one rebalance
            await this.subject.rebalance({
                tickLower: this.initialTickLow - 60,
                tickUpper: this.initialTickHigh - 60,
            });

            // second swap, FT this time
            await mint(
                "USDC",
                testSigner.address,
                BigNumber.from(10).pow(6).mul(100000)
            );

            await this.peripheryContract.connect(testSigner).swap({
                marginEngine: this.marginEngine,
                isFT: true,
                notional: BigNumber.from(10).pow(6).mul(100000),
                sqrtPriceLimitX96: MAX_SQRT_RATIO.sub(1),
                tickLower: -60,
                tickUpper: 60,
                marginDelta: BigNumber.from(10).pow(6).mul(100000),
            });

            const positions: {
                tickLower: number;
                tickUpper: number;
            }[] = [
                {
                    tickLower: this.initialTickLow,
                    tickUpper: this.initialTickHigh,
                },
                {
                    tickLower: this.initialTickLow - 60,
                    tickUpper: this.initialTickHigh - 60,
                },
            ];

            let currentTimestamp = (
                await hre.ethers.provider.getBlock("latest")
            ).timestamp;

            const termStartTimestamp = Number(
                ethers.utils.formatEther(
                    await this.marginEngineContract.callStatic.termStartTimestampWad()
                )
            );

            const termEndTimestamp = Number(
                ethers.utils.formatEther(
                    await this.marginEngineContract.callStatic.termEndTimestampWad()
                )
            );

            let fixedCashflow = 0;
            let margins = BigNumber.from(0);
            const positionInfos = [];
            for (const position of positions) {
                positionInfos.push(
                    await this.marginEngineContract.callStatic.getPosition(
                        this.subject.address,
                        position.tickLower,
                        position.tickUpper
                    )
                );

                fixedCashflow +=
                    (positionInfos[positionInfos.length - 1].fixedTokenBalance *
                        0.01 *
                        (termEndTimestamp - termStartTimestamp)) /
                    YEAR_IN_SECONDS;
                margins = margins.add(
                    positionInfos[positionInfos.length - 1].margin
                );
            }

            // advance time and check tvl after each day
            while (currentTimestamp < termEndTimestamp) {
                const apyStartNow = Number(
                    ethers.utils.formatEther(
                        await this.rateOracleContract.callStatic.getApyFromTo(
                            termStartTimestamp,
                            currentTimestamp
                        )
                    )
                );
                const apyHistoricalLookback = Number(
                    ethers.utils.formatEther(
                        await this.rateOracleContract.callStatic.getApyFromTo(
                            currentTimestamp - lookbackWindow,
                            currentTimestamp
                        )
                    )
                );

                let variableCashflowLower = 0;
                let variableCashflowUpper = 0;

                for (const positionInfo of positionInfos) {
                    variableCashflowLower +=
                        positionInfo.variableTokenBalance *
                        ((apyStartNow *
                            (currentTimestamp - termStartTimestamp)) /
                            YEAR_IN_SECONDS +
                            (apyHistoricalLookback *
                                (1 - estimatedAPYDecimalDelta) *
                                (termEndTimestamp - currentTimestamp)) /
                                YEAR_IN_SECONDS);

                    variableCashflowUpper +=
                        positionInfo.variableTokenBalance *
                        ((apyStartNow *
                            (currentTimestamp - termStartTimestamp)) /
                            YEAR_IN_SECONDS +
                            (apyHistoricalLookback *
                                (1 + estimatedAPYDecimalDelta) *
                                (termEndTimestamp - currentTimestamp)) /
                                YEAR_IN_SECONDS);
                }

                const groundTruthTvlLower = margins.add(
                    Math.floor(fixedCashflow + variableCashflowLower)
                );
                const groundTruthTvlUpper = margins.add(
                    Math.floor(fixedCashflow + variableCashflowUpper)
                );

                await this.subject.updateTvl();
                const tvl = await this.subject.tvl();
                expect(tvl[0][0].toNumber()).to.be.closeTo(
                    groundTruthTvlLower.toNumber(),
                    groundTruthTvlLower.div(1000).toNumber()
                );

                expect(tvl[1][0].toNumber()).to.be.closeTo(
                    groundTruthTvlUpper.toNumber(),
                    groundTruthTvlUpper.div(1000).toNumber()
                );

                // advance time by 1 day
                await network.provider.send("evm_increaseTime", [24 * 60 * 60]);
                await network.provider.send("evm_mine", []);
                currentTimestamp += 24 * 60 * 60;
            }
        });
    });

    describe("Chained operations", () => {
        beforeEach(async () => {
            await withSigner(this.subject.address, async (signer) => {
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
                        await this.usdc.balanceOf(this.subject.address)
                    );
            });
        });

        it("rebalance to prev tracked pos + settle", async () => {
            const { test } = await getNamedAccounts();
            const testSigner = await hre.ethers.getSigner(test);
            await this.usdc
                .connect(testSigner)
                .approve(this.periphery, BigNumber.from(10).pow(27));

            for (let i = 0; i < 10; i++) {
                await mint(
                    "USDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(1000000000)
                );

                await this.preparePush();
                await this.subject.push(
                    [this.usdc.address],
                    [BigNumber.from(10).pow(6).mul(1000000000)],
                    encodeToBytes([], [])
                );

                await mint(
                    "USDC",
                    testSigner.address,
                    BigNumber.from(10).pow(6).mul(100000000)
                );

                await this.peripheryContract.connect(testSigner).swap({
                    marginEngine: this.marginEngine,
                    isFT: i % 2,
                    notional: BigNumber.from(10).pow(6).mul(100000000),
                    sqrtPriceLimitX96:
                        i % 2 ? MAX_SQRT_RATIO.sub(1) : MIN_SQRT_RATIO.add(1),
                    tickLower: -60,
                    tickUpper: 60,
                    marginDelta: BigNumber.from(10).pow(6).mul(100000000),
                });

                const currentTick = (await this.vammContract.vammVars()).tick;

                const newPosition = {
                    tickLower: currentTick - (currentTick % 60) - 600,
                    tickUpper: currentTick - (currentTick % 60) + 600,
                };
                await this.subject.rebalance(newPosition);

                const currentPosition = await this.subject.currentPosition();
                expect(currentPosition.tickLower).to.be.equal(
                    newPosition.tickLower
                );
                expect(currentPosition.tickUpper).to.be.equal(
                    newPosition.tickUpper
                );
            }

            let trackedPositions = await getTrackedPositions();
            expect(trackedPositions.length).to.be.eq(8);

            // rebalance to fourth position
            await this.subject.rebalance(trackedPositions[4]);

            trackedPositions = await getTrackedPositions();
            expect(trackedPositions.length).to.be.eq(7);
            const currentPosition = await this.subject.currentPosition();
            expect(currentPosition.tickLower).to.be.equal(
                trackedPositions[4].tickLower
            );
            expect(currentPosition.tickUpper).to.be.equal(
                trackedPositions[4].tickUpper
            );

            // advance time by 60 days to reach maturity
            await network.provider.send("evm_increaseTime", [
                60 * 24 * 60 * 60,
            ]);
            await network.provider.send("evm_mine", []);

            const batch_size = 3;
            for (let i = 0; i < trackedPositions.length; i += 3) {
                await this.subject.settleVault(batch_size);
                for (
                    let j = i;
                    j < i + batch_size && j < trackedPositions.length;
                    j++
                ) {
                    const positionInfo =
                        await this.marginEngineContract.callStatic.getPosition(
                            this.subject.address,
                            trackedPositions[j].tickLower,
                            trackedPositions[j].tickUpper
                        );

                    expect(positionInfo.isSettled).to.be.eq(true);
                }
            }
        });
    });
});
