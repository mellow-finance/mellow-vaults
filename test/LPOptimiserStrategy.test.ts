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
        await this.subject.connect(this.admin).setConstants(
            -1000, 
            BigNumber.from("100000000000000000"), 
            BigNumber.from("1500000000000000000"), 
            60
            );
    });

    describe("Rebalance Logic", async () => {
        it( "Check if in-range position needs to be rebalanced", async () => {
            await this.subject.connect(this.admin).setTickValues(3000, 0, 6000);
            const result = await this.subject.rebalanceCheck();
            expect(result).to.be.equal(false);
        })
        it("Check if out-of-range position needs to be rebalanced", async () => {
            await this.subject.connect(this.admin).setTickValues(8000, 0, 6000);
            const result = await this.subject.rebalanceCheck();
            expect(result).to.be.equal(true);
        })
        // it("No need to rebalance position", async () => {
        //     const currentFixedRateWad = BigNumber.from("2000000000000000000");
        //     await this.subject.connect(this.admin).setTickValues(3000, 0, 6000);
        //     await expect(this.subject.connect(this.admin).rebalance(currentFixedRateWad)).to.be.revertedWith("RNN");
        // })
        it("Rebalance the position and return new ticks (max_poss_lower_bound < delta)", async () => {
            const currentFixedRateWad = BigNumber.from("2000000000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(newTicks[0]).to.be.equal(-5220);
            expect(newTicks[1]).to.be.equal(-4020);
        })
        it("Rebalance the position and return new ticks (max_poss_lower_bound > delta)", async () => {
            const currentFixedRateWad = BigNumber.from("1000000000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(newTicks[0]).to.be.equal(-900);
            expect(newTicks[1]).to.be.equal(1080);
        })
    })

    describe("NearestTickMultiple Function Logic", async () => {
        it("Testing nearestTickMultiple function for newTick < 0 and |newTick| < tickSpacing", async () => {
            const newTick = -10;
            const tickSpacing = 60;
            const result = await this.subject.callStatic.nearestTickMultiple(newTick, tickSpacing);
            expect(result).to.be.equal(60);
        })
        it("Testing nearestTickMultiple function for newTick < 0 and |newTick| > tickSpacing", async () => {
            const newTick = -100;
            const tickSpacing = 60;
            const result = await this.subject.callStatic.nearestTickMultiple(newTick, tickSpacing);
            expect(result).to.be.equal(-60);
        })
        it("Testing nearestTickMultiple function for newTick > 0 and newTick < tickSpacing", async () => {
            const newTick = 10;
            const tickSpacing = 60;
            const result = await this.subject.callStatic.nearestTickMultiple(newTick, tickSpacing);
            expect(result).to.be.equal(0);
        })
        it("Testing nearestTickMultiple function for newTick > 0 and newTick > tickSpacing", async () => {
            const newTick = 100;
            const tickSpacing = 60;
            const result = await this.subject.callStatic.nearestTickMultiple(newTick, tickSpacing);
            expect(result).to.be.equal(120);
        })
    })

    describe("deltaWad Calculation Logic", async () => {
        it("deltaWad = 0.001", async () => {
            const currentFixedRateWad = BigNumber.from("101000000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(newTicks[0]).to.be.equal(16020);
            expect(newTicks[1]).to.be.equal(69060);
        })
        it("deltaWad < 0.001", async () => {
            const currentFixedRateWad = BigNumber.from("100500000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(newTicks[0]).to.be.equal(16080);
            expect(newTicks[1]).to.be.equal(76020);
        })
        it("deltaWad = 1000", async () => {
            const currentFixedRateWad = BigNumber.from("1000100000000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(newTicks[0]).to.be.equal(-5220);
            expect(newTicks[1]).to.be.equal(-4020);
        })
        it("deltaWad > 1000", async () => {
            const currentFixedRateWad = BigNumber.from("2000100000000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(newTicks[0]).to.be.equal(-5220);
            expect(newTicks[1]).to.be.equal(-4020);
        })
    })

    describe("Rebalance Event", async () => {
        it("Rebalance event was emitted after successful call on rebalance()", async () => {
            const currentFixedRateWad = BigNumber.from("2000100000000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(
                Object.entries(this.lPOptimiserStrategy.interface.events).some(
                    ([k, v]: any) => v.name === "Rebalanced"
                )
            ).to.be.equal(true);
        })
        it("StrategyDeployment event was emitted after successful deployment of strategy", async () => {
            const currentFixedRateWad = BigNumber.from("2000100000000000000000");
            await this.subject.connect(this.admin).setTickValues(7000, 0, 6000);
            const newTicks = await this.subject.connect(this.admin).callStatic.rebalance(currentFixedRateWad);
            expect(
                Object.entries(this.lPOptimiserStrategy.interface.events).some(
                    ([k, v]: any) => v.name === "StrategyDeployment"
                )
            ).to.be.equal(true);
        })
    })
});
