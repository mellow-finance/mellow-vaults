import { deployments, ethers, getNamedAccounts } from "hardhat";
import { combineVaults, PermissionIdsLibrary, setupVault } from "../deploy/0000_utils";
import { checkStateOfVoltzOpenedPositions, encodeToBytes, mint, sleep, withSigner } from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20Vault, IMarginEngine, IVAMM, LPOptimiserStrategy, VoltzVault } from "./types";
import hre from "hardhat";
import { BigNumber } from "ethers";
import { expect } from "chai";

type CustomContext = {
    voltzVault: VoltzVault;
    erc20Vault: ERC20Vault;
    preparePush: () => any;
    marginEngine: string;
    marginEngineContract: IMarginEngine;
    vammContract: IVAMM;
}

type DeployOptions = {};

contract<LPOptimiserStrategy, DeployOptions, CustomContext>("LPOptimiserStrategy", function () {
    this.timeout(200000);

    const LOW_TICK = 0;
    const HIGH_TICK = 60;

    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { marginEngine, voltzPeriphery } = await getNamedAccounts();
                this.marginEngine = marginEngine;
                this.marginEngineContract = await ethers.getContractAt("IMarginEngine", this.marginEngine) as IMarginEngine;
                this.vammContract = await ethers.getContractAt("IVAMM", await this.marginEngineContract.vamm()) as IVAMM;

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

                let voltzVaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                await setupVault(
                    hre,
                    voltzVaultNft,
                    "VoltzVaultGovernance",
                    {
                        createVaultArgs: [
                            tokens,
                            this.deployer.address,
                            this.marginEngine,
                            LOW_TICK,
                            HIGH_TICK
                        ],
                    }
                );

                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                const { deploy } = deployments;

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

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.voltzVault = await ethers.getContractAt(
                    "VoltzVault",
                    voltzVault
                );

                let strategyDeployParams = await deploy("LPOptimiserStrategy", {
                    from: this.deployer.address,
                    contract: "LPOptimiserStrategy",
                    args: [
                        this.erc20Vault.address,
                        this.voltzVault.address,
                        this.admin.address,
                    ],
                    log: true,
                    autoMine: true,
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, voltzVaultNft],
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
                await sleep(await this.protocolGovernance.governanceDelay());
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
                        periphery: voltzPeriphery
                    });
                await sleep(86400);
                await this.voltzVaultGovernance
                    .connect(this.admin)
                    .commitDelayedProtocolParams();

                this.preparePush = async () => {

                    await withSigner("0xb527e950fc7c4f581160768f48b3bfa66a7de1f0", async (s) => {
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
                    });
                };

                this.grantPermissionsVoltzVaults = async () => {
                    let tokenId = await ethers.provider.send(
                        "eth_getStorageAt",
                        [
                            this.voltzVault.address,
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
                };

                return this.subject;
            }
        )
    });

    beforeEach(async () => {
        await this.deploymentFixture();
        await this.subject.connect(this.admin).setLogProximity(-1000);
    });

    describe("new rebalance function", async () => {
        it( "rebalance get the current position", async () => {
            await this.subject.connect(this.admin).setCurrentTick(3000);
            const result = await this.subject.rebalanceCheck();
            expect(result).to.be.equal(false);
        })
        it("No need to rebalance position", async () => {
            const currentFixedRateWad = BigNumber.from("2000000000000000000");
            await this.subject.connect(this.admin).setCurrentTick(3000);
            await expect(this.subject.connect(this.admin).rebalance(currentFixedRateWad)).to.be.revertedWith("RNN");
        })
        it("Rebalance the position and return new ticks", async () => {
            const currentFixedRateWad = BigNumber.from("2000000000000000000");
            await this.subject.connect(this.admin).setCurrentTick(7000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad); // without callStatic this only returns the contract receipt
            expect(newTicks[0]).to.be.equal(-5280);
            expect(newTicks[1]).to.be.equal(-4020);
        })
    })

    describe("one signal", async () => {
        for (let signal of [1, 2, 3]) {
            for (let leverage of [1, 10]) {
                const tagSignal =
                    (signal === 1)
                        ? "SHORT"
                        : (signal === 2)
                            ? "LONG"
                            : "EXIT";

                it(`signal ${tagSignal} with leverage ${leverage}x`, async () => {
                    await this.preparePush();

                    await mint(
                        "USDC",
                        this.voltzVault.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );

                    await this.voltzVault.push(
                        [this.usdc.address],
                        [
                            BigNumber.from(10).pow(6).mul(3000),
                        ],
                        encodeToBytes(
                            ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                            [
                                BigNumber.from(0),
                                BigNumber.from(0),
                                BigNumber.from(0),
                                false,
                                0,
                                0,
                                false,
                                0
                            ]
                        )
                    );

                    await this.grantPermissionsVoltzVaults();
                    await this.subject.connect(this.admin).update(signal, BigNumber.from(10).pow(18).mul(leverage), false);

                    const position = await this.marginEngineContract.callStatic.getPosition(
                        this.voltzVault.address,
                        LOW_TICK,
                        HIGH_TICK
                    );

                    if (signal === 1) {
                        expect(position.variableTokenBalance.eq(BigNumber.from(10).pow(6).mul(3000).mul(-leverage)));
                    }

                    if (signal === 2) {
                        expect(position.variableTokenBalance.eq(BigNumber.from(10).pow(6).mul(3000).mul(leverage)));
                    }

                    if (signal === 3) {
                        expect(position.variableTokenBalance.eq(BigNumber.from(0)));
                    }

                    expect(position.margin.lte(BigNumber.from(10).pow(6).mul(3000)));
                    expect(position.margin.gte(BigNumber.from(10).pow(6).mul(2950)));
                })
            }
        }
    });

    describe("two signals", async () => {
        for (let firstSignal of [1, 2, 3]) {
            for (let secondSignal of [1, 2, 3]) {
                for (let firstLeverage of [1, 10]) {
                    for (let secondLeverage of [1, 10]) {
                        const tagFirstSignal =
                            (firstSignal === 1)
                                ? "SHORT"
                                : (firstSignal === 2)
                                    ? "LONG"
                                    : "EXIT";

                        const tagSecondSignal =
                            (secondSignal === 1)
                                ? "SHORT"
                                : (firstSignal === 2)
                                    ? "LONG"
                                    : "EXIT";

                        it(`${tagFirstSignal} then ${tagSecondSignal} with leverage ${secondLeverage}x`, async () => {
                            await this.preparePush();

                            await mint(
                                "USDC",
                                this.voltzVault.address,
                                BigNumber.from(10).pow(6).mul(3000)
                            );

                            await this.voltzVault.push(
                                [this.usdc.address],
                                [
                                    BigNumber.from(10).pow(6).mul(3000),
                                ],
                                encodeToBytes(
                                    ["int256", "int256", "uint160", "bool", "int24", "int24", "bool", "uint256"],
                                    [
                                        BigNumber.from(0),
                                        BigNumber.from(0),
                                        BigNumber.from(0),
                                        false,
                                        0,
                                        0,
                                        false,
                                        0
                                    ]
                                )
                            );

                            await this.grantPermissionsVoltzVaults();

                            {
                                await this.subject.connect(this.admin).update(firstSignal, BigNumber.from(10).pow(18).mul(firstLeverage), false);

                                const position = await this.marginEngineContract.callStatic.getPosition(
                                    this.voltzVault.address,
                                    LOW_TICK,
                                    HIGH_TICK
                                );

                                if (firstSignal === 1) {
                                    expect(position.variableTokenBalance.eq(BigNumber.from(10).pow(6).mul(3000).mul(-firstLeverage)));
                                }

                                if (firstSignal == 2) {
                                    expect(position.variableTokenBalance.eq(BigNumber.from(10).pow(6).mul(3000).mul(firstLeverage)));
                                }

                                if (firstSignal == 3) {
                                    expect(position.variableTokenBalance.eq(BigNumber.from(0)));
                                }

                                expect(position.margin.lte(BigNumber.from(10).pow(6).mul(3000)));
                                expect(position.margin.gte(BigNumber.from(10).pow(6).mul(2950)));
                            }

                            {
                                await this.subject.connect(this.admin).update(secondSignal, BigNumber.from(10).pow(18).mul(secondLeverage), false);

                                const position = await this.marginEngineContract.callStatic.getPosition(
                                    this.voltzVault.address,
                                    LOW_TICK,
                                    HIGH_TICK
                                );

                                if (secondSignal === 1) {
                                    expect(position.variableTokenBalance.eq(BigNumber.from(10).pow(6).mul(3000).mul(-secondLeverage)));
                                }

                                if (secondSignal == 2) {
                                    expect(position.variableTokenBalance.eq(BigNumber.from(10).pow(6).mul(3000).mul(secondLeverage)));
                                }

                                if (secondSignal == 3) {
                                    expect(position.variableTokenBalance.eq(BigNumber.from(0)));
                                }

                                expect(position.margin.lte(BigNumber.from(10).pow(6).mul(3000)));
                                expect(position.margin.gte(BigNumber.from(10).pow(6).mul(2950)));
                            }
                        })
                    }
                }
            }
        }
    });
});