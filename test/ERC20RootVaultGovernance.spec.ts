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
import { address, pit, uint256 } from "./library/property";
import { Arbitrary, tuple } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { delayedProtocolPerVaultParamsBehaviour } from "./behaviors/vaultGovernanceDelayedProtocolPerVaultParams";
import { DelayedProtocolPerVaultParamsStruct, InternalParamsStruct } from "./types/IERC20RootVaultGovernance";
import { BigNumber } from "@ethersproject/bignumber";

type CustomContext = {
    nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};
type DeployOptions = {
    internalParams?: InternalParamsStruct;
    managementFeeChargeDelay?: BigNumber;
    skipInit?: boolean;
};

contract<ERC20RootVaultGovernance, DeployOptions, CustomContext>(
    "ERC20RootVaultGovernance",
    function () {
        const MAX_PROTOCOL_FEE = 50000000;
        const MAX_MANAGEMENT_FEE = 100000000;
        const MAX_PERFORMANCE_FEE = 500000000;

        before(async () => {
            this.ownerSigner = await addSigner(randomAddress());
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();

                    const { address } = await deployments.get("ERC20RootVaultGovernance"); 
                    this.subject = await ethers.getContractAt(
                        "ERC20RootVaultGovernance",
                        address
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        const delayedProtocolPerVaultParams: Arbitrary<DelayedProtocolPerVaultParamsStruct> =
            tuple(uint256.filter((x) => x.lt(MAX_PROTOCOL_FEE))).map(
                ([protocolFee]) => ({
                    protocolFee: BigNumber.from(protocolFee),
                })
            );

        describe("#constructor", () => {
            it("deploys a new contract", async () => {
                expect(this.subject.address).to.not.equals(ethers.constants.AddressZero);
            });
            it("initializes MAX_PROTOCOL_FEE", async () => {
                expect(await (this.subject as Contract).MAX_PROTOCOL_FEE()).to.deep.equal(BigNumber.from(MAX_PROTOCOL_FEE));
            });
            it("initializes MAX_MANAGEMENT_FEE", async () => {
                expect(await (this.subject as Contract).MAX_MANAGEMENT_FEE()).to.deep.equal(BigNumber.from(MAX_MANAGEMENT_FEE));
            });
            it("initializes MAX_PERFORMANCE_FEE", async () => {
                expect(await (this.subject as Contract).MAX_PERFORMANCE_FEE()).to.deep.equal(BigNumber.from(MAX_PERFORMANCE_FEE));
            });
        });

        delayedProtocolPerVaultParamsBehaviour.call(this as any, delayedProtocolPerVaultParams);
    }
);
