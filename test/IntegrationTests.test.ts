import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    addSigner,
    now,
    randomAddress,
    sleep,
    sleepTo,
    withSigner,
    randomNft,
    sortAddresses,
    mint,
    MintableToken,
} from "./library/Helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import {
    AaveVault,
    AaveVaultGovernance,
    ERC20RootVault,
    ERC20RootVaultGovernance,
    ERC20Vault,
    ERC20VaultGovernance,
    MockERC165,
    ProtocolGovernance,
    VaultRegistry,
    YearnVault,
    YearnVaultGovernance,
} from "./types";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/dist/types";
import { CREATE_VAULT } from "./library/PermissionIdsLibrary";
import { address, pit, RUNS } from "./library/property";
import { integer } from "fast-check";
import Exceptions from "./library/Exceptions";
import {
    VAULT_INTERFACE_ID,
    VAULT_REGISTRY_INTERFACE_ID,
} from "./library/Constants";
import { contract } from "./library/setup";
import { PermissionIdsLibrary__factory } from "./types/factories/PermissionIdsLibrary__factory";
import { BigNumber } from "@ethersproject/bignumber";

type CustomContext = {
    ownerSigner: SignerWithAddress;
    yearnNft: number;
    yaernVault: YearnVault;
    erc20Nft: number;
    erc20Vault: ERC20Vault;
    erc20RootNft: number;
};
type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration test",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    await deployments.fixture();
                    this.ownerSigner = await addSigner(randomAddress());
                    await this.protocolGovernance
                        .connect(this.admin)
                        .stagePermissionGrants(this.ownerSigner.address, [
                            CREATE_VAULT,
                        ]);
                    await sleep(this.governanceDelay);
                    await this.protocolGovernance
                        .connect(this.admin)
                        .commitPermissionGrants(this.ownerSigner.address);
                    const { vault: erc20VaultAddress, nft: nftERC20 } =
                        await this.erc20VaultGovernance.callStatic.createVault(
                            sortAddresses([
                                this.usdc.address,
                                this.wbtc.address,
                            ]),
                            this.ownerSigner.address
                        );
                    await this.erc20VaultGovernance.createVault(
                        sortAddresses([this.usdc.address, this.wbtc.address]),
                        this.ownerSigner.address
                    );
                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20VaultAddress
                    );
                    this.erc20Nft = Number(nftERC20);

                    const { vault: yearnVaultAddress, nft: nftYearn } =
                        await this.yearnVaultGovernance.callStatic.createVault(
                            sortAddresses([
                                this.usdc.address,
                                this.wbtc.address,
                            ]),
                            this.ownerSigner.address
                        );
                    await this.yearnVaultGovernance.createVault(
                        sortAddresses([this.usdc.address, this.wbtc.address]),
                        this.ownerSigner.address
                    );
                    this.yaernVault = await ethers.getContractAt(
                        "YearnVault",
                        yearnVaultAddress
                    );
                    this.yearnNft = Number(nftYearn);

                    let erc20RootVaultGovernance: ERC20RootVaultGovernance =
                        await ethers.getContract("ERC20RootVaultGovernance");

                    await this.vaultRegistry
                        .connect(this.ownerSigner)
                        .approve(
                            this.erc20RootVaultGovernance.address,
                            this.yearnNft
                        );
                    await this.vaultRegistry
                        .connect(this.ownerSigner)
                        .approve(
                            this.erc20RootVaultGovernance.address,
                            this.erc20Nft
                        );

                    const {
                        vault: erc20RootVaultAddress,
                        nft: nftERC20RootVault,
                    } = await erc20RootVaultGovernance
                        .connect(this.ownerSigner)
                        .callStatic.createVault(
                            sortAddresses([
                                this.usdc.address,
                                this.wbtc.address,
                            ]),
                            this.mStrategy.address,
                            [this.erc20Nft, this.yearnNft],
                            this.ownerSigner.address
                        );

                    await erc20RootVaultGovernance
                        .connect(this.ownerSigner)
                        .createVault(
                            sortAddresses([
                                this.usdc.address,
                                this.wbtc.address,
                            ]),
                            this.mStrategy.address,
                            [this.erc20Nft, this.yearnNft],
                            this.ownerSigner.address
                        );

                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVaultAddress
                    );
                    this.erc20RootNft = Number(nftERC20RootVault);

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
            this.startTimestamp = now();
            await sleepTo(this.startTimestamp);
        });

        describe("Integration Test", () => {
            it("creates vaults", async () => {
                expect(this.erc20Vault.address).to.not.eq(
                    ethers.constants.AddressZero
                );
                expect(this.yaernVault.address).to.not.eq(
                    ethers.constants.AddressZero
                );
                expect(this.subject.address).to.not.be.equal(
                    ethers.constants.AddressZero
                );
            });

            describe("#deposit + withdraw", () => {
                it("does not fail", async () => {
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.ownerSigner.address]);
                    await this.erc20RootVaultGovernance
                        .connect(this.admin)
                        .setStrategyParams(this.erc20RootNft, {
                            tokenLimitPerAddress: 1000,
                            tokenLimit: 2000,
                        });
                    await mint("WBTC", this.ownerSigner.address, 1000);
                    await mint("USDC", this.ownerSigner.address, 1000);
                    await this.wbtc
                        .connect(this.ownerSigner)
                        .approve(this.subject.address, 1000);
                    await this.usdc
                        .connect(this.ownerSigner)
                        .approve(this.subject.address, 1000);
                    await expect(
                        this.subject
                            .connect(this.ownerSigner)
                            .deposit([1000, 1000], 1)
                    ).to.not.be.reverted;
                    for (var x in await this.subject.tvl()) {
                        console.log(Number(x));
                    }
                    await this.subject
                        .connect(this.ownerSigner)
                        .withdraw(this.ownerSigner.address, 1, [1, 1]);
                    for (var x in await this.subject.tvl()) {
                        console.log(Number(x));
                    }
                });
            });
        });
    }
);
