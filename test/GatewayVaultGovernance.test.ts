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
import { GatewayVaultGovernance } from "./types/GatewayVaultGovernance";
import { setupDefaultContext, TestContext } from "./library/setup";
import { Context, Suite } from "mocha";
import { equals } from "ramda";
import { address, pit } from "./library/property";
import { BigNumber } from "@ethersproject/bignumber";
import { Arbitrary, array, constant, nat } from "fast-check";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { vaultGovernanceBehavior } from "./behaviors/vaultGovernance";
import {
    InternalParamsStruct,
    InternalParamsStructOutput,
} from "./types/IVaultGovernance";
import { DelayedStrategyParamsStruct } from "./types/IGatewayVaultGovernance";
import { ERC20VaultGovernance } from "./types";
import { Signer } from "ethers";

type CustomContext = {
    nft: number;
    erc20Nft: number;
    strategySigner: SignerWithAddress;
    ownerSigner: SignerWithAddress;
};

type DeployOptions = {
    internalParams?: InternalParamsStructOutput;
    skipInit?: boolean;
};

// @ts-ignore
describe("GatewayVaultGovernance", function (this: TestContext<
    GatewayVaultGovernance,
    DeployOptions
> &
    CustomContext) {
    before(async () => {
        // @ts-ignore
        await setupDefaultContext.call(this);
        this.deploymentFixture = deployments.createFixture(
            async (_, options?: DeployOptions) => {
                await deployments.fixture();
                const {
                    internalParams = {
                        protocolGovernance: this.protocolGovernance.address,
                        registry: this.vaultRegistry.address,
                    },
                    skipInit = false,
                } = options || {};
                const { address } = await deployments.deploy(
                    "GatewayVaultGovernanceTest",
                    {
                        from: this.deployer.address,
                        contract: "GatewayVaultGovernance",
                        args: [internalParams],
                        autoMine: true,
                    }
                );
                this.subject = await ethers.getContractAt(
                    "GatewayVaultGovernance",
                    address
                );
                this.ownerSigner = await addSigner(randomAddress());
                this.strategySigner = await addSigner(randomAddress());
                const erc20VaultGovernance: ERC20VaultGovernance =
                    await ethers.getContract("ERC20VaultGovernance");
                const tokenAddresses = this.tokens.map((x: any) => x.address);

                await erc20VaultGovernance.deployVault(
                    tokenAddresses,
                    [],
                    this.ownerSigner.address
                );
                this.erc20Nft = (
                    await this.vaultRegistry.vaultsCount()
                ).toNumber();

                if (!skipInit) {
                    const { address: factoryAddress } =
                        await deployments.deploy("GatewayVaultFactoryTest", {
                            from: this.deployer.address,
                            contract: "GatewayVaultFactory",
                            args: [this.subject.address],
                            autoMine: true,
                        });
                    await this.subject.initialize(factoryAddress);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .setPendingVaultGovernancesAdd([this.subject.address]);
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitVaultGovernancesAdd();
                    await this.vaultRegistry
                        .connect(this.ownerSigner)
                        .setApprovalForAll(this.subject.address, true);
                    await this.subject
                        .connect(this.ownerSigner)
                        .deployVault(
                            tokenAddresses,
                            ethers.utils.defaultAbiCoder.encode(
                                ["uint256[]"],
                                [[this.erc20Nft]]
                            ),
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

    const delayedStrategyParams: Arbitrary<DelayedStrategyParamsStruct> =
        constant(this.erc20Nft).map((erc20nft) => ({
            redirects: [BigNumber.from(this.erc20Nft)],
        }));

    describe("#constructor", () => {
        it("deploys a new contract", async () => {
            expect(ethers.constants.AddressZero).to.not.eq(
                this.subject.address
            );
        });
    });

    // @ts-ignore
    vaultGovernanceBehavior.call(this, {
        delayedStrategyParams,
        deployVaultFunction: async (
            deployer: Signer,
            tokenAddresses: string[],
            owner: string
        ) => {
            const erc20VaultGovernance: ERC20VaultGovernance =
                await ethers.getContract("ERC20VaultGovernance");
            const deployerAddress = await deployer.getAddress();
            await erc20VaultGovernance
                .connect(deployer)
                .deployVault(tokenAddresses, [], deployerAddress);
            const erc20Nft = (
                await this.vaultRegistry.vaultsCount()
            ).toNumber();
            await this.vaultRegistry
                .connect(deployer)
                .setApprovalForAll(this.subject.address, true);
            await this.subject
                .connect(deployer)
                .deployVault(
                    tokenAddresses,
                    ethers.utils.defaultAbiCoder.encode(
                        ["uint256[]"],
                        [[erc20Nft]]
                    ),
                    owner
                );
            const nft = await this.vaultRegistry.vaultsCount();
            await this.vaultRegistry
                .connect(deployer)
                .transferFrom(deployerAddress, owner, nft);
        },
        ...this,
    });
});
