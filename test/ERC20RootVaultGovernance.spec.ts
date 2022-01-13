import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
} from "./library/Helpers";
import Exceptions from "./library/Exceptions";
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import {
    ERC20RootVaultGovernance,
    DelayedProtocolParamsStruct,
    DelayedProtocolParamsStructOutput,
} from "./types/ERC20RootVaultGovernance"
import { Contract } from "@ethersproject/contracts";
import { contract, setupDefaultContext, TestContext } from "./library/setup";
import { address, pit } from "./library/property";
import { Arbitrary } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStruct } from "./types/IERC20RootVaultGovernance";
import { BigNumber } from "ethers";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};
type DeployOptions = {
    internalParams?: InternalParamsStruct;
    yearnVaultRegistry?: string;
    skipInit?: boolean;
};

contract<ERC20RootVaultGovernance, DeployOptions, CustomContext>(
    "ERC20RootVaultGovernance",
    function () {
        before(async () => {
            this.ownerSigner = await addSigner(randomAddress());
            // @ts-ignore
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get("ERC20RootVaultGovernance");
                    this.subject = await ethers.getContractAt("ERC20RootVaultGovernance", address);
                    // todo: skipInit & deploy options
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(this.subject.address).to.eql(ethers.constants.AddressZero);
            });
            it("initializes MAX_PROTOCOL_FEE", async () => {
                expect(await (this.subject as Contract).MAX_PROTOCOL_FEE()).to.eql(1);
            });
            it("initializes MAX_MANAGEMENT_FEE", async () => {
                expect(await (this.subject as Contract).MAX_MANAGEMENT_FEE()).to.eql(1);
            });
            it("initializes MAX_PERFORMANCE_FEE", async () => {
                expect(await (this.subject as Contract).MAX_PERFORMANCE_FEE()).to.eql(1);
            });
        });
    
        describe("#stagedDelayedProtocolParams", () => {
            it("returns staged delayed protocol params", async () => {
                const params: DelayedProtocolParamsStruct = {
                    managementFeeChargeDelay: 1,
                };
                await this.erc20RootVaultGovernance.stageDelayedProtocolParams(params);
                expect(await this.erc20RootVaultGovernance.stagedDelayedProtocolParams()).to.eql(params);
            });
    
            describe("properties", () => {
                it("@property: updates by #stageDelayedProtocolParams", async () => {});
                it("@property: resets by #commitDelayedProtocolParams", async () => {});
            });
            describe("access control", () => {
                it("allowed: any address", async () => {});
            });
        });
    
        describe("#stagedDelayedProtocolPerVaultParams", () => {
            it("returns staged delayed protocol params per vault", async () => {});
    
            describe("properties", () => {
                it("@property: updates by #stageDelayedProtocolPerVaultParams", async () => {});
                it("@property: resets by #commitDelayedProtocolPerVaultParams", async () => {});
            });
    
            describe("access control", () => {
                it("allowed: any address", async () => {});
            });
        });
    
        describe("#stagedDelayedStrategyParams", () => {
            it("returns staged delayed strategy params", async () => {});
    
            describe("properties", () => {
                it("@property: updates by #stageDelayedStrategyParams", async () => {});
                it("@property: resets by #commitDelayedStrategyParams", async () => {});
            });
    
            describe("access control", () => {
                it("allowed: any address", async () => {});
            });
        });
    
        describe("#delayedStrategyParams", () => {
            it("returns delayed strategy params", async () => {});
    
            describe("properties", () => {
                it("@property: doesn't update by #stageDelayedStrategyParams", async () => {});
                it("@property: updates by #commitDelayedStrategyParams", async () => {});
            });
    
            describe("access control", () => {
                it("allowed: any address", async () => {});
            });
        });
    
        describe("#strategyParams", () => {
            it("returns strategy params", async () => {});
    
            describe("access control", () => {
                it("allowed: any address", async () => {});
            });
        });
    
        describe("#stageDelayedStrategyParams", () => {
            it("stages delayed strategy params", async () => {});
    
            it("emits StageDelayedStrategyParams event", async () => {});
    
            describe("edge cases", () => {
                describe("when params.managementFee > MAX_MANAGEMENT_FEE", () => {
                    it("reverts with LIMIT_OVERFLOW", async () => {});
                });
    
                describe("when params.performanceFee > MAX_PERFORMANCE_FEE", () => {
                    it("reverts with LIMIT_OVERFLOW", async () => {});
                });
    
                describe("when initial delayed strategy params are empty", () => {
                    it("allows to commit staged params instantly", async () => {});
                });
    
                describe("when passed unknown nft", () => {
                    it("works", async () => {});
                });
            });
    
            describe("access control", () => {
                it("allowed: strategy", async () => {});
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });
    
        describe("#commitDelayedStrategyParams", () => {
            it("commits delayed strategy params", async () => {});
    
            it("emits CommitDelayedStrategyParams event", async () => {});
    
            describe("edge cases", () => {
                describe("when nothing has been staged yet", () => {
                    it("reverts with NULL", async () => {});
                });
    
                describe("when governance delay has not passed yet", () => {
                    it("reverts with TIMESTAMP", async () => {});
                });
            });
    
            describe("access control", () => {
                it("allowed: strategy", async () => {});
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });
    
        describe("#stageDelayedProtocolPerVaultParams", () => {
            it("stages delayed protocol params per vault", async () => {});
    
            it("emits StageDelayedProtocolPerVaultParams event", async () => {});
    
            describe("edge cases", () => {
                describe("when params.protocolFee > MAX_PROTOCOL_FEE", () => {
                    it("reverts with LIMIT_OVERFLOW", async () => {});
                });
    
                describe("when initial delayed protocol params are empty", () => {
                    it("allows to commit staged params instantly", async () => {});
                });
    
                describe("when passed unknown nft", () => {
                    it("works", async () => {});
                });
            });
    
            describe("access control", () => {
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });
    
        describe("#commitDelayedProtocolPerVaultParams", () => {
            it("commits delayed protocol params per vault", async () => {});
    
            it("emits CommitDelayedProtocolPerVaultParams event", async () => {});
    
            describe("edge cases", () => {
                describe("when nothing has been staged yet", () => {
                    it("reverts with NULL", async () => {});
                });
    
                describe("when governance delay has not passed yet", () => {
                    it("reverts with TIMESTAMP", async () => {});
                });
            });
    
            describe("access control", () => {
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });
    
        describe("#setStrategyParams", () => {
            it("sets strategy params", async () => {});
            it("emits SetStrategyParams event", async () => {});
    
            describe("access control", () => {
                it("allowed: strategy", async () => {});
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });
    
        describe("#stageDelayedProtocolParams", () => {
            it("stages delayed protocol params", async () => {});
            it("emits StageDelayedProtocolParams event", async () => {});
    
            describe("edge cases", () => {
                describe("when initial delayed protocol params are empty", () => {
                    it("allows to commit staged params instantly", async () => {});
                });
            });
    
            describe("access control", () => {
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });
    
        describe("#commitDelayedProtocolParams", () => {
            it("commits delayed protocol params", async () => {});
            it("emits CommitDelayedProtocolParams event", async () => {});
    
            describe("edge cases", () => {
                describe("when nothing has been staged yet", () => {
                    it("reverts with NULL", async () => {});
                });
    
                describe("when governance delay has not passed yet", () => {
                    it("reverts with TIMESTAMP", async () => {});
                });
            });
    
            describe("access control", () => {
                it("allowed: admin", async () => {});
                it("denied: deployer", async () => {});
                it("denied: random address", async () => {});
            });
        });
    }
);
