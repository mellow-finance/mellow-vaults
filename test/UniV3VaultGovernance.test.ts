import { Assertion, expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    toObject,
    withSigner,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import {
    DelayedProtocolParamsStruct,
    UniV3VaultGovernance,
} from "./types/UniV3VaultGovernance";
import { setupDefaultContext, TestContext } from "./library/setup";
import { Context, Suite } from "mocha";
import { equals } from "ramda";
import { address, pit, RUNS } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, hexa, hexaString, nat, tuple } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import {
    InternalParamsStruct,
    InternalParamsStructOutput,
} from "./types/IVaultGovernance";
import { ERC20, IUniswapV3Pool, UniV3Vault } from "./types";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};
type DeploymentOptions = {
    internalParams?: InternalParamsStructOutput;
    positionManager?: string;
    skipInit?: boolean;
};

// @ts-ignore
xdescribe("UniV3VaultGovernance", function (this: TestContext<
    UniV3VaultGovernance,
    DeploymentOptions
> &
    CustomContext) {
    before(async () => {
        // @ts-ignore
        await setupDefaultContext.call(this);
        const positionManagerAddress = (await getNamedAccounts())
            .uniswapV3PositionManager;
        this.deploymentFixture = deployments.createFixture(
            async (_, options?: DeploymentOptions) => {
                await deployments.fixture();
                const {
                    internalParams = {
                        protocolGovernance: this.protocolGovernance.address,
                        registry: this.vaultRegistry.address,
                    },
                    positionManager = positionManagerAddress,
                    skipInit = false,
                } = options || {};
                const { address } = await deployments.deploy(
                    "UniV3VaultGovernanceTest",
                    {
                        from: this.deployer.address,
                        contract: "UniV3VaultGovernance",
                        args: [internalParams, { positionManager }],
                        autoMine: true,
                    }
                );
                this.subject = await ethers.getContractAt(
                    "UniV3VaultGovernance",
                    address
                );
                this.ownerSigner = await addSigner(randomAddress());
                this.strategySigner = await addSigner(randomAddress());

                if (!skipInit) {
                    await this.protocolGovernance
                        .connect(this.admin)
                        .setPendingVaultGovernancesAdd([this.subject.address]);
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitVaultGovernancesAdd();
                    await this.subject.createVault(
                        this.tokens.slice(0, 2).map((x: any) => x.address),
                        3000,
                        this.ownerSigner.address
                    );
                    this.nft = (
                        await this.vaultRegistry.vaultsCount()
                    ).toNumber();
                    await this.vaultRegistry
                        .connect(this.ownerSigner)
                        .approve(this.strategySigner.address, this.nft);
                }
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
        this.startTimestamp = now();
        await sleepTo(this.startTimestamp);
    });

    const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> = tuple(
        address,
        address
    ).map(([positionManager, oracle]) => ({ positionManager, oracle }));

    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(ethers.constants.AddressZero).to.not.eq(
                this.subject.address
            );
        });

        describe("edge cases", () => {
            describe("when positionManager address is 0", () => {
                it("reverts", async () => {
                    await deployments.fixture();
                    await expect(
                        deployments.deploy("UniV3VaultGovernance", {
                            from: this.deployer.address,
                            args: [
                                {
                                    protocolGovernance:
                                        this.protocolGovernance.address,
                                    registry: this.vaultRegistry.address,
                                },
                                {
                                    positionManager:
                                        ethers.constants.AddressZero,
                                },
                            ],
                            autoMine: true,
                        })
                    ).to.be.revertedWith(Exceptions.ADDRESS_ZERO);
                });
            });
        });
    });

    xdescribe("#createVault", () => {
        describe("properties", () => {
            pit(
                "reverts for any options with length != 32 or != 0",
                { numRuns: RUNS.mid },
                nat(100)
                    .filter((x) => x != 0 && x != 32)
                    .map((x) => x * 2) // avoid malformed hex data, should be caught by evm
                    .chain((len) =>
                        hexaString({ minLength: len, maxLength: len })
                    )
                    .map((x) => `0x${x}`),
                async (bytes: string) => {
                    await expect(
                        this.subject.createVault(
                            this.tokens
                                .slice(0, 2)
                                .map((x: ERC20) => x.address),
                            3000,
                            this.ownerSigner.address
                        )
                    ).to.be.revertedWith(Exceptions.INVALID_OPTIONS);
                    return true;
                }
            );
            pit(
                "reverts for any fee != 1, 500, 3000, 10000",
                { numRuns: RUNS.mid },
                nat(10000)
                    .filter(
                        (x) => x != 1 && x != 500 && x != 3000 && x != 10000
                    )
                    .map((x) => BigNumber.from(x).toHexString())
                    .map((x) => ethers.utils.hexZeroPad(x, 32)),
                async (bytes: string) => {
                    await expect(
                        this.subject.createVault(
                            this.tokens
                                .slice(0, 2)
                                .map((x: ERC20) => x.address),
                            3000,
                            this.ownerSigner.address
                        )
                    ).to.be.revertedWith(Exceptions.UNISWAP_POOL_NOT_FOUND);
                    return true;
                }
            );
        });
        describe("edge cases", () => {
            describe("when options are 0 length bytes", () => {
                it("deploys a vault for 0.3% fee pool", async () => {
                    await this.subject.createVault(
                        [this.weth.address, this.usdc.address]
                            .map((x) => x.toLowerCase())
                            .sort(),
                        [],
                        this.ownerSigner.address
                    );
                    const nft = await this.vaultRegistry.vaultsCount();
                    const address = await this.vaultRegistry.vaultForNft(nft);
                    const vault: UniV3Vault = await ethers.getContractAt(
                        "UniV3Vault",
                        address
                    );
                    const poolAddress = await vault.pool();
                    const pool: IUniswapV3Pool = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        poolAddress
                    );
                    expect(3000).to.eq(await pool.fee());
                });
            });
            describe("when options are bytes with length 32", () => {
                it("deploys a vault with fee equals to uint256 represented by 32 bytes of options", async () => {
                    await this.subject.createVault(
                        [this.weth.address, this.usdc.address]
                            .map((x) => x.toLowerCase())
                            .sort(),
                        ethers.utils.hexZeroPad(
                            BigNumber.from(500).toHexString(),
                            32
                        ),
                        this.ownerSigner.address
                    );
                    const nft = await this.vaultRegistry.vaultsCount();
                    const address = await this.vaultRegistry.vaultForNft(nft);
                    const vault: UniV3Vault = await ethers.getContractAt(
                        "UniV3Vault",
                        address
                    );
                    const poolAddress = await vault.pool();
                    const pool: IUniswapV3Pool = await ethers.getContractAt(
                        "IUniswapV3Pool",
                        poolAddress
                    );
                    expect(500).to.eq(await pool.fee());
                });
            });
        });
    });

    // @ts-ignore
    vaultGovernanceBehavior.call(this, {
        delayedProtocolParams,
        ...this,
    });
});
