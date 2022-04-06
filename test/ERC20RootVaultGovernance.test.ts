import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleepTo,
    withSigner,
} from "./library/Helpers";
import {
    DelayedProtocolParamsStruct,
    ERC20RootVaultGovernance,
} from "./types/ERC20RootVaultGovernance";
import { contract } from "./library/setup";
import { address } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, integer, tuple, boolean } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStruct } from "./types/IVaultGovernance";
import {
    DelayedProtocolPerVaultParamsStruct,
    DelayedStrategyParamsStruct,
    OperatorParamsStruct,
} from "./types/IERC20RootVaultGovernance";
import { ERC20_ROOT_VAULT_GOVERNANCE } from "./library/Constants";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

type DeployOptions = {
    internalParams?: InternalParamsStruct;
};

contract<ERC20RootVaultGovernance, DeployOptions, CustomContext>(
    "ERC20RootVaultGovernance",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();
                    const { address: singleton } = await deployments.get(
                        "ERC20RootVault"
                    );
                    const {
                        internalParams = {
                            protocolGovernance: this.protocolGovernance.address,
                            registry: this.vaultRegistry.address,
                            singleton,
                        },
                    } = options || {};
                    const { address } = await deployments.deploy(
                        "ERC20RootVaultGovernanceTest",
                        {
                            from: this.deployer.address,
                            contract: "ERC20RootVaultGovernance",
                            args: [
                                internalParams,
                                {
                                    managementFeeChargeDelay:
                                        BigNumber.from(86400),
                                    oracle: this.mellowOracle.address,
                                },
                            ],
                            autoMine: true,
                        }
                    );
                    this.subject = await ethers.getContractAt(
                        "ERC20RootVaultGovernance",
                        address
                    );
                    this.ownerSigner = await addSigner(randomAddress());
                    this.strategySigner = await addSigner(randomAddress());
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
            this.startTimestamp = now();
            await sleepTo(this.startTimestamp);
        });

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true if this contract supports ${ERC20_ROOT_VAULT_GOVERNANCE} interface`, async () => {
                expect(
                    await this.subject.supportsInterface(
                        ERC20_ROOT_VAULT_GOVERNANCE
                    )
                ).to.be.true;
            });

            describe("access control:", () => {
                it("allowed: any address", async () => {
                    await withSigner(randomAddress(), async (s) => {
                        await expect(
                            this.subject
                                .connect(s)
                                .supportsInterface(ERC20_ROOT_VAULT_GOVERNANCE)
                        ).to.not.be.reverted;
                    });
                });
            });
        });

        const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> =
            tuple(integer({ min: 0, max: 10 ** 6 }), address).map(
                ([num, oracle]) => ({
                    managementFeeChargeDelay: BigNumber.from(num),
                    oracle,
                })
            );

        const delayedStrategyParams: Arbitrary<DelayedStrategyParamsStruct> =
            tuple(
                address,
                address,
                boolean(),
                integer({ min: 0, max: 10 ** 6 }),
                integer({ min: 0, max: 10 ** 6 })
            ).map(
                ([
                    strategyTreasury,
                    strategyPerformanceTreasury,
                    privateVault,
                    numManagementFee,
                    numPerformanceFee,
                ]) => ({
                    strategyTreasury,
                    strategyPerformanceTreasury,
                    privateVault,
                    managementFee: BigNumber.from(numManagementFee),
                    performanceFee: BigNumber.from(numPerformanceFee),
                    depositCallback: ethers.constants.AddressZero,
                    withdrawCallback: ethers.constants.AddressZero,
                    rebalanceDeadline: ethers.constants.Zero
                })
            );

        const delayedProtocolPerVaultParams: Arbitrary<DelayedProtocolPerVaultParamsStruct> =
            integer({ min: 0, max: 10 ** 6 }).map((num) => ({
                protocolFee: BigNumber.from(num),
            }));

        const operatorParams: Arbitrary<OperatorParamsStruct> = boolean().map(
            (disableDeposit) => ({
                disableDeposit,
            })
        );

        vaultGovernanceBehavior.call(this, {
            delayedStrategyParams,
            delayedProtocolParams,
            delayedProtocolPerVaultParams,
            operatorParams,
            rootVaultGovernance: true,
            ...this,
        });
    }
);
