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
    ERC20RootVaultGovernance,
} from "./types/ERC20RootVaultGovernance";
import { REGISTER_VAULT } from "./library/PermissionIdsLibrary";
import { contract } from "./library/setup";
import { address } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, integer, tuple } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import { InternalParamsStruct } from "./types/IVaultGovernance";

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
            ``;
            this.startTimestamp = now();
            await sleepTo(this.startTimestamp);
        });

        const delayedProtocolParams: Arbitrary<DelayedProtocolParamsStruct> =
            tuple(integer({ min: 0, max: 10 ** 6 }), address).map(
                ([num, oracle]) => ({
                    managementFeeChargeDelay: BigNumber.from(num),
                    oracle,
                })
            );

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.subject.address
                );
            });
        });

        vaultGovernanceBehavior.call(this, {
            delayedProtocolParams,
            rootVaultGovernance: true,
            ...this,
        });
    }
);
