import { deployments, ethers, getNamedAccounts } from "hardhat";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import { mint, sleep, withSigner } from "./library/Helpers";
import { contract } from "./library/setup";
import {
    ERC20Vault,
    IMarginEngine,
    IVAMM,
    LPOptimiserStrategy,
    VoltzVault,
} from "./types";
import hre from "hardhat";
import { BigNumber, utils } from "ethers";
import { expect } from "chai";

type CustomContext = {
    voltzVaults: VoltzVault[];
    erc20Vault: ERC20Vault;
    preparePush: () => any;
    marginEngine: string;
    marginEngineContract: IMarginEngine;
    vammContract: IVAMM;
};

type DeployOptions = {};

contract<LPOptimiserStrategy, DeployOptions, CustomContext>(
    "LPOptimiserStrategy",
    function () {
        this.timeout(200000);

        const leverage = 10;
        const marginMultiplierPostUnwind = 2;
        const noOfVoltzVaults = 2;

        before(async () => {
            this.deploymentFixtureOne = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const LOW_TICK = 0;
                    const HIGH_TICK = 6000;

                    await deployments.fixture();
                    const { read } = deployments;

                    const { marginEngine, voltzPeriphery } =
                        await getNamedAccounts();
                    this.marginEngine = marginEngine;
                    this.marginEngineContract = (await ethers.getContractAt(
                        "IMarginEngine",
                        this.marginEngine
                    )) as IMarginEngine;
                    this.vammContract = (await ethers.getContractAt(
                        "IVAMM",
                        await this.marginEngineContract.vamm()
                    )) as IVAMM;

                    await this.usdc.approve(
                        this.marginEngine,
                        ethers.constants.MaxUint256
                    );

                    await this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(this.usdc.address, [
                            PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                        ]);
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitPermissionGrants(this.usdc.address);

                    const tokens = [this.usdc.address].map((t) =>
                        t.toLowerCase()
                    );

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let voltzVaultNfts = Array.from(
                        Array(noOfVoltzVaults).keys()
                    ).map((val) => startNft + val);
                    let erc20VaultNft = startNft + noOfVoltzVaults;

                    this.voltzVaultHelperSingleton = (
                        await ethers.getContract("VoltzVaultHelper")
                    ).address;

                    for (let nft of voltzVaultNfts) {
                        await setupVault(hre, nft, "VoltzVaultGovernance", {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                this.marginEngine,
                                this.voltzVaultHelperSingleton,
                                {
                                    tickLower: LOW_TICK,
                                    tickUpper: HIGH_TICK,
                                    leverageWad: utils.parseEther(
                                        leverage.toString()
                                    ),
                                    marginMultiplierPostUnwindWad:
                                        utils.parseEther(
                                            marginMultiplierPostUnwind.toString()
                                        ),
                                },
                            ],
                        });
                    }

                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

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

                    let strategyDeployParams = await deploy(
                        "LPOptimiserStrategy",
                        {
                            from: this.deployer.address,
                            contract: "LPOptimiserStrategy",
                            args: [
                                this.erc20Vault.address,
                                this.voltzVaults.map((val) => val.address),
                                this.voltzVaults.map((_) => {
                                    return {
                                        sigmaWad: "100000000000000000",
                                        maxPossibleLowerBoundWad:
                                            "1500000000000000000",
                                        proximityWad: "100000000000000000",
                                        weight: "1",
                                    };
                                }),
                                this.admin.address,
                            ],
                            log: true,
                            autoMine: true,
                        }
                    );

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
                        .stageValidator(
                            this.usdc.address,
                            usdcValidator.address
                        );
                    await sleep(
                        await this.protocolGovernance.governanceDelay()
                    );
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitValidator(this.usdc.address);

                    this.subject = await ethers.getContractAt(
                        "LPOptimiserStrategy",
                        strategyDeployParams.address
                    );

                    for (let address of [
                        this.deployer.address,
                        this.subject.address,
                        this.erc20Vault.address,
                    ]) {
                        await mint(
                            "USDC",
                            address,
                            BigNumber.from(10).pow(6).mul(4000)
                        );
                        await this.usdc.approve(
                            address,
                            ethers.constants.MaxUint256
                        );
                    }

                    await this.usdc.approve(
                        this.marginEngine,
                        ethers.constants.MaxUint256
                    );

                    await this.usdc.transfer(
                        this.subject.address,
                        BigNumber.from(10).pow(6).mul(3)
                    );

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
                                    this.vammContract
                                        .connect(s)
                                        .setIsAlpha(false)
                                ).to.not.be.reverted;
                            }
                        );
                    };

                    this.grantPermissionsVoltzVaults = async () => {
                        for (let i = 0; i < noOfVoltzVaults; i++) {
                            let tokenId = await ethers.provider.send(
                                "eth_getStorageAt",
                                [
                                    this.voltzVaults[i].address,
                                    "0x4", // address of _nft
                                ]
                            );
                            await withSigner(
                                this.erc20RootVault.address,
                                async (erc20RootVaultSigner) => {
                                    await this.vaultRegistry
                                        .connect(erc20RootVaultSigner)
                                        .approve(this.subject.address, tokenId);
                                }
                            );
                        }
                    };

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixtureOne();
            await this.grantPermissionsVoltzVaults();
        });

        describe("Rebalance Logic", async () => {
            it("Check if in-range position needs to be rebalanced", async () => {
                await withSigner(this.subject.address, async (s) => {
                    await this.voltzVaults[0].connect(s).rebalance({
                        tickLower: -3000,
                        tickUpper: 0,
                    });
                });

                const currentFixedRateWad = BigNumber.from(
                    "1100000000000000000"
                );

                const tick = (await this.vammContract.vammVars()).tick;
                expect(tick).to.be.eq(-1069);

                const vaultParams = await this.subject.getVaultParams(0);
                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: "100000000000000000",
                    maxPossibleLowerBoundWad:
                        vaultParams.maxPossibleLowerBoundWad,
                    proximityWad: vaultParams.proximityWad,
                    weight: vaultParams.weight,
                });

                const result = await this.subject.rebalanceCheck(
                    0,
                    currentFixedRateWad
                );
                expect(result).to.be.equal(false);
            });
            it("Check if out-of-range position needs to be rebalanced", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1000000000000000000"
                );
                const result = await this.subject.callStatic.rebalanceCheck(
                    0,
                    currentFixedRateWad
                );
                expect(result).to.be.equal(true);
            });
            it("Rebalance the position and return new ticks (max_poss_lower_bound < delta)", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "2000000000000000000"
                );

                if (
                    await this.subject.callStatic.rebalanceCheck(
                        0,
                        currentFixedRateWad
                    )
                ) {
                    const newTicks = await this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad);
                    expect(newTicks[0]).to.be.equal(-5220);
                    expect(newTicks[1]).to.be.equal(-4020);
                } else {
                    throw new Error("Position does not need to be rebalanced");
                }
            });

            it("Rebalance the position and return new ticks (max_poss_lower_bound > delta)", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1000000000000000000"
                );
                const newTicks = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(newTicks[0]).to.be.equal(-900);
                expect(newTicks[1]).to.be.equal(1080);
            });
        });

        describe("NearestTickMultiple Function Logic", async () => {
            it("Testing nearestTickMultiple function for newTick < 0 and |newTick| < tickSpacing", async () => {
                const newTick = -10;
                const tickSpacing = 60;
                const result =
                    await this.subject.callStatic.nearestTickMultiple(
                        newTick,
                        tickSpacing
                    );
                expect(result).to.be.equal(60);
            });
            it("Testing nearestTickMultiple function for newTick < 0 and |newTick| > tickSpacing", async () => {
                const newTick = -100;
                const tickSpacing = 60;
                const result =
                    await this.subject.callStatic.nearestTickMultiple(
                        newTick,
                        tickSpacing
                    );
                expect(result).to.be.equal(-60);
            });
            it("Testing nearestTickMultiple function for newTick > 0 and newTick < tickSpacing", async () => {
                const newTick = 10;
                const tickSpacing = 60;
                const result =
                    await this.subject.callStatic.nearestTickMultiple(
                        newTick,
                        tickSpacing
                    );
                expect(result).to.be.equal(0);
            });
            it("Testing nearestTickMultiple function for newTick > 0 and newTick > tickSpacing", async () => {
                const newTick = 100;
                const tickSpacing = 60;
                const result =
                    await this.subject.callStatic.nearestTickMultiple(
                        newTick,
                        tickSpacing
                    );
                expect(result).to.be.equal(120);
            });
        });

        describe("deltaWad Calculation Logic", async () => {
            it("deltaWad = 0.001", async () => {
                const currentFixedRateWad =
                    BigNumber.from("101000000000000000");
                const newTicks = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(newTicks[0]).to.be.equal(15600);
                expect(newTicks[1]).to.be.equal(46080);
            });
            it("0 < deltaWad < 0.001", async () => {
                const currentFixedRateWad =
                    BigNumber.from("100010000000000000"); // 0.10001

                const vaultParams = await this.subject.getVaultParams(0);
                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: "100000000000000000",
                    maxPossibleLowerBoundWad:
                        vaultParams.maxPossibleLowerBoundWad,
                    proximityWad: vaultParams.proximityWad,
                    weight: vaultParams.weight,
                });

                const newTicks = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(newTicks[0]).to.be.equal(15600);
                expect(newTicks[1]).to.be.equal(46080);
            });
            it("deltaWad = 1000", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1000100000000000000000"
                );
                const newTicks = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(newTicks[0]).to.be.equal(-5220);
                expect(newTicks[1]).to.be.equal(-4020);
            });
            it("deltaWad > 1000", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "2000100000000000000000"
                );
                const newTicks = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(newTicks[0]).to.be.equal(-5220);
                expect(newTicks[1]).to.be.equal(-4020);
            });
        });

        describe("Rebalance Event", async () => {
            it("Rebalance event was emitted after successful call on rebalance()", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "2000100000000000000000"
                );
                await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(
                    Object.entries(
                        this.lPOptimiserStrategy.interface.events
                    ).some(([k, v]: any) => v.name === "RebalancedTicks")
                ).to.be.equal(true);
            });
            it("StrategyDeployment event was emitted after successful deployment of strategy", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "2000100000000000000000"
                );
                await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(
                    Object.entries(
                        this.lPOptimiserStrategy.interface.events
                    ).some(([k, v]: any) => v.name === "StrategyDeployment")
                ).to.be.equal(true);
            });
        });

        describe("Check for underflow of deltaWad calculation", async () => {
            it("_sigmaWad > currentFixedRateWad s.t. deltaWad < 0", async () => {
                const currentFixedRateWad =
                    BigNumber.from("100000000000000000"); // 0.1

                const vaultParams0 = await this.subject.getVaultParams(0);
                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: "200000000000000000",
                    maxPossibleLowerBoundWad:
                        vaultParams0.maxPossibleLowerBoundWad,
                    proximityWad: vaultParams0.proximityWad,
                    weight: vaultParams0.weight,
                });

                const vaultParams1 = await this.subject.getVaultParams(0);
                expect(vaultParams1.sigmaWad).to.be.eq("200000000000000000");

                const newTicks = await this.subject
                    .connect(this.admin)
                    .callStatic.rebalanceTicks(0, currentFixedRateWad);
                expect(newTicks[0]).to.be.equal(8940);
                expect(newTicks[1]).to.be.equal(46080);
            });
        });

        describe("Check if the VoltzVault updated ticks to the new ones from the strategy", async () => {
            it("Confirm the ticks are updated when rebalance is triggered", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1000000000000000000"
                );

                if (await this.subject.rebalanceCheck(0, currentFixedRateWad)) {
                    await this.subject
                        .connect(this.admin)
                        .rebalanceTicks(0, currentFixedRateWad);
                    const newTicks = await this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad);

                    const position =
                        await this.voltzVaults[0].currentPosition();

                    expect(position.tickLower).to.be.equal(
                        newTicks.newTickLower
                    );
                    expect(position.tickUpper).to.be.equal(
                        newTicks.newTickUpper
                    );
                } else {
                    throw new Error("Position does not need to be rebalanced");
                }
            });
        });

        describe("Rebalance into a shorter range", async () => {
            it("_sigmaWad = 0.05", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1500000000000000000"
                );
                const vaultParams0 = await this.subject.getVaultParams(0);
                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: "50000000000000000",
                    maxPossibleLowerBoundWad:
                        vaultParams0.maxPossibleLowerBoundWad,
                    proximityWad: vaultParams0.proximityWad,
                    weight: vaultParams0.weight,
                });

                const vaultParams1 = await this.subject.getVaultParams(0);
                expect(vaultParams1.sigmaWad).to.be.eq("50000000000000000");

                if (await this.subject.rebalanceCheck(0, currentFixedRateWad)) {
                    const newTicks = await this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad);

                    expect(newTicks.newTickLower).to.be.equal(-4320);
                    expect(newTicks.newTickUpper).to.be.equal(-3660);

                    const newFixedLower = 1.0001 ** -newTicks.newTickUpper;
                    expect(newFixedLower).to.be.closeTo(1.45, 0.03);

                    const newFixedUpper = 1.0001 ** -newTicks.newTickLower;
                    expect(newFixedUpper).to.be.closeTo(1.55, 0.03);
                } else {
                    throw new Error("Position does not need to be rebalanced");
                }
            });

            it("Rebalance with currentFixedRate > max allowable i.e. 1001%", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1001000000000000000000"
                ); // 1001%

                if (await this.subject.rebalanceCheck(0, currentFixedRateWad)) {
                    const newTicks = await this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad);

                    expect(newTicks.newTickLower).to.be.equal(-5220);
                    expect(newTicks.newTickUpper).to.be.equal(-4020);

                    const newFixedLower = 1.0001 ** -newTicks.newTickUpper;
                    expect(newFixedLower).to.be.closeTo(1.5, 0.03);

                    const newFixedUpper = 1.0001 ** -newTicks.newTickLower;
                    expect(newFixedUpper).to.be.closeTo(1.7, 0.03);
                } else {
                    throw new Error("Position does not need to be rebalanced");
                }
            });
        });

        describe("Rebalance with small value of proximity", async () => {
            it("proximity = 0.1 => logProx ~ -23040", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1000000000000000000"
                );

                const vaultParams0 = await this.subject.getVaultParams(0);
                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: vaultParams0.sigmaWad,
                    maxPossibleLowerBoundWad:
                        vaultParams0.maxPossibleLowerBoundWad,
                    proximityWad: "100000000000000000",
                    weight: vaultParams0.weight,
                });

                const vaultParams1 = await this.subject.getVaultParams(0);
                expect(vaultParams1.proximityWad).to.be.eq(
                    "100000000000000000"
                );

                if (await this.subject.rebalanceCheck(0, currentFixedRateWad)) {
                    const newTicks = await this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad);

                    expect(newTicks.newTickLower).to.be.equal(-900);
                    expect(newTicks.newTickUpper).to.be.equal(1080);

                    const newFixedLower = 1.0001 ** -newTicks.newTickUpper;
                    expect(newFixedLower).to.be.closeTo(0.9, 0.03);

                    const newFixedUpper = 1.0001 ** -newTicks.newTickLower;
                    expect(newFixedUpper).to.be.closeTo(1.1, 0.03);
                } else {
                    throw new Error("Position does not need to be rebalanced");
                }
            });

            it("Proximity = 0 case (happy path)", async () => {
                const vaultParams0 = await this.subject.getVaultParams(0);
                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: vaultParams0.sigmaWad,
                    maxPossibleLowerBoundWad:
                        vaultParams0.maxPossibleLowerBoundWad,
                    proximityWad: "0",
                    weight: vaultParams0.weight,
                });

                const vaultParams1 = await this.subject.getVaultParams(0);
                expect(vaultParams1.proximityWad).to.be.eq("0");

                const currentFixedRateWad =
                    BigNumber.from("900000000000000000");

                const result = await this.subject.callStatic.rebalanceCheck(
                    0,
                    currentFixedRateWad
                );
                expect(result).to.be.equal(false);
            });

            it("maxPossibleLowerBound = 1e16 i.e. effectively 0", async () => {
                // Test if values of deltaWad below 1e16 are allowed
                const currentFixedRateWad = BigNumber.from(
                    "1000000000000000000"
                ); // 1

                const vaultParams0 = await this.subject.getVaultParams(0);
                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: "999900000000000000",
                    maxPossibleLowerBoundWad: "10000000000000000",
                    proximityWad: vaultParams0.proximityWad,
                    weight: vaultParams0.weight,
                });

                if (await this.subject.rebalanceCheck(0, currentFixedRateWad)) {
                    const newTicks = await this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad);

                    expect(newTicks.newTickLower).to.be.equal(-6900);
                    expect(newTicks.newTickUpper).to.be.equal(46080);

                    const newFixedLower = 1.0001 ** -newTicks.newTickUpper;
                    expect(newFixedLower).to.be.closeTo(0, 0.03);

                    const newFixedUpper = 1.0001 ** -newTicks.newTickLower;
                    expect(newFixedUpper).to.be.closeTo(2, 0.03);
                } else {
                    throw new Error("Position does not need to be rebalanced");
                }
            });
        });

        describe("Setters and Getters", async () => {
            it("Set parameters", async () => {
                const vaultParams0 = await this.subject.getVaultParams(0);
                expect(vaultParams0.sigmaWad).to.be.eq("100000000000000000");
                expect(vaultParams0.maxPossibleLowerBoundWad).to.be.eq(
                    "1500000000000000000"
                );
                expect(vaultParams0.proximityWad).to.be.eq(
                    "100000000000000000"
                );
                expect(vaultParams0.weight).to.be.eq("1");

                await this.subject.connect(this.admin).setVaultParams(0, {
                    sigmaWad: "200000000000000000",
                    maxPossibleLowerBoundWad: "400000000000000000",
                    proximityWad: "200000000000000000",
                    weight: "2",
                });
                const vaultParams1 = await this.subject.getVaultParams(0);

                expect(vaultParams1.sigmaWad).to.be.eq("200000000000000000");
                expect(vaultParams1.maxPossibleLowerBoundWad).to.be.eq(
                    "400000000000000000"
                );
                expect(vaultParams1.proximityWad).to.be.eq(
                    "200000000000000000"
                );
                expect(vaultParams1.weight).to.be.eq("2");
            });

            it("Set parameters for the second pool", async () => {
                {
                    const vaultParams = await this.subject.getVaultParams(0);
                    expect(vaultParams.sigmaWad).to.be.eq("100000000000000000");
                    expect(vaultParams.maxPossibleLowerBoundWad).to.be.eq(
                        "1500000000000000000"
                    );
                    expect(vaultParams.proximityWad).to.be.eq(
                        "100000000000000000"
                    );
                    expect(vaultParams.weight).to.be.eq("1");
                }

                {
                    const vaultParams = await this.subject.getVaultParams(1);
                    expect(vaultParams.sigmaWad).to.be.eq("100000000000000000");
                    expect(vaultParams.maxPossibleLowerBoundWad).to.be.eq(
                        "1500000000000000000"
                    );
                    expect(vaultParams.proximityWad).to.be.eq(
                        "100000000000000000"
                    );
                    expect(vaultParams.weight).to.be.eq("1");
                }

                await this.subject.connect(this.admin).setVaultParams(1, {
                    sigmaWad: "200000000000000000",
                    maxPossibleLowerBoundWad: "400000000000000000",
                    proximityWad: "200000000000000000",
                    weight: "2",
                });

                {
                    const vaultParams = await this.subject.getVaultParams(0);
                    expect(vaultParams.sigmaWad).to.be.eq("100000000000000000");
                    expect(vaultParams.maxPossibleLowerBoundWad).to.be.eq(
                        "1500000000000000000"
                    );
                    expect(vaultParams.proximityWad).to.be.eq(
                        "100000000000000000"
                    );
                    expect(vaultParams.weight).to.be.eq("1");
                }

                {
                    const vaultParams = await this.subject.getVaultParams(1);
                    expect(vaultParams.sigmaWad).to.be.eq("200000000000000000");
                    expect(vaultParams.maxPossibleLowerBoundWad).to.be.eq(
                        "400000000000000000"
                    );
                    expect(vaultParams.proximityWad).to.be.eq(
                        "200000000000000000"
                    );
                    expect(vaultParams.weight).to.be.eq("2");
                }
            });

            it("Set parameters for non-existing vault", async () => {
                await expect(this.subject.getVaultParams(noOfVoltzVaults)).to.be
                    .reverted;

                await expect(
                    this.subject
                        .connect(this.admin)
                        .setVaultParams(noOfVoltzVaults, {
                            sigmaWad: "200000000000000000",
                            maxPossibleLowerBoundWad: "400000000000000000",
                            proximityWad: "200000000000000000",
                            weight: "2",
                        })
                ).to.be.reverted;
            });

            it("Get the tickSpacing from the vamm", async () => {
                const tickSpacing = await this.vammContract.tickSpacing();

                // Currently VAMM sets tickSpacing to 60
                expect(tickSpacing).to.be.equal(60);
            });
        });

        describe("Fixed rate to tick conversion function", async () => {
            it("Fixed rate = 1% => tick = 0", async () => {
                const fixedRate = BigNumber.from("1000000000000000000"); // 1
                const tick = await this.subject
                    .connect(this.admin)
                    .callStatic.convertFixedRateToTick(fixedRate);

                expect(tick).to.be.equal(0);
            });
            it("Fixed rate = 0.01% => tick", async () => {
                const fixedRate = BigNumber.from("100000000000000000"); // 0.1
                const tick = await this.subject
                    .connect(this.admin)
                    .callStatic.convertFixedRateToTick(fixedRate);

                expect(tick).to.be.equal(
                    BigNumber.from("23027002203301009434868")
                );
            });
            it("Fixed rate = 0.001% => tick", async () => {
                const fixedRate = BigNumber.from("10000000000000000"); // 0.01
                const tick = await this.subject
                    .connect(this.admin)
                    .callStatic.convertFixedRateToTick(fixedRate);

                expect(tick).to.be.equal(
                    BigNumber.from("46054004406602018966781")
                );
            });
            it("Fixed rate = 10% => tick", async () => {
                const fixedRate = BigNumber.from("10000000000000000"); // 0.01
                const tick = await this.subject
                    .connect(this.admin)
                    .callStatic.convertFixedRateToTick(fixedRate);

                expect(tick).to.be.equal(
                    BigNumber.from("46054004406602018966781")
                );
            });
        });

        describe("Tick to fixed rate conversion function", async () => {
            it("tick = 0 => Fixed rate = 1%", async () => {
                const tick = 0;
                const fixedRate = await this.subject
                    .connect(this.admin)
                    .convertTickToFixedRate(tick);

                expect(fixedRate).to.be.equal("1000000000000000000");
            });
            it("tick = 1200 => Fixed rate = 0.886%", async () => {
                const tick = 1200;
                const fixedRate = await this.subject
                    .connect(this.admin)
                    .convertTickToFixedRate(tick);

                expect(fixedRate).to.be.equal("886925757900998720");
            });
            it("tick = -1200 => Fixed rate = 1.127%", async () => {
                const tick = -1200;
                const fixedRate = await this.subject
                    .connect(this.admin)
                    .convertTickToFixedRate(tick);

                expect(fixedRate).to.be.equal("1127490087069523309");
            });
            it("tick = 42000 => Fixed rate = 0.015%", async () => {
                const tick = 42000;
                const fixedRate = await this.subject
                    .connect(this.admin)
                    .convertTickToFixedRate(tick);

                expect(fixedRate).to.be.equal("14998726012319204");
            });
        });

        describe("Privilege tests sad path", async () => {
            it("Require admin privilege test for logProx setter", async () => {
                const vaultParams = await this.subject.getVaultParams(0);
                await expect(
                    this.subject.setVaultParams(0, vaultParams)
                ).to.be.revertedWith("FRB");
            });
            it("Require require at least operator privilege test for rebalance ticks function", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1000000000000000000"
                ); // 1%
                await expect(
                    this.subject.callStatic.rebalanceTicks(
                        0,
                        currentFixedRateWad
                    )
                ).to.be.revertedWith("FRB");
            });
        });

        describe("Privilege tests happy path", async () => {
            it("Admin privilege test for Proximity setter", async () => {
                const vaultParams = await this.subject.getVaultParams(0);
                await expect(
                    this.subject
                        .connect(this.admin)
                        .callStatic.setVaultParams(0, vaultParams)
                ).to.not.be.reverted;
            });
            it("Require at least operator privilege test for rebalance ticks function", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "1000000000000000000"
                ); // 1%
                await expect(
                    this.subject
                        .connect(this.operator)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad)
                ).to.not.be.reverted;
            });
            it("Require statement test for rebalanceTicks function SAD PATH", async () => {
                const currentFixedRateWad =
                    BigNumber.from("900000000000000000"); // 0.9%
                await expect(
                    this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad)
                ).to.be.revertedWith("RNN");
            });

            it("Require statement test for rebalanceTicks function HAPPY PATH", async () => {
                const currentFixedRateWad = BigNumber.from(
                    "2000000000000000000"
                ); // 2%
                await expect(
                    this.subject
                        .connect(this.admin)
                        .callStatic.rebalanceTicks(0, currentFixedRateWad)
                ).to.not.be.reverted;
            });
        });
    }
);
