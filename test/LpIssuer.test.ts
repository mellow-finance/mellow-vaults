import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import Exceptions from "./library/Exceptions";
import { ERC20, LpIssuerGovernance } from "./library/Types";
import { LpIssuer, ProtocolGovernance, VaultRegistry } from "./library/Types";
import { deploySystem } from "./library/Deployments";

describe("LpIssuer", () => {
    let deployer: SignerWithAddress;
    let admin: SignerWithAddress;
    let stranger: SignerWithAddress;
    let strategy: SignerWithAddress;
    let treasury: SignerWithAddress;
    let LpIssuer: LpIssuer;
    let vaultRegistry: VaultRegistry;
    let protocolGovernance: ProtocolGovernance;
    let LpIssuerGovernance: LpIssuerGovernance;
    let lpIssuerNft: number;
    let gatewayNft: number;
    let tokens: ERC20[];
    let revert: Function;

    before(async () => {
        [deployer, admin, stranger, treasury, strategy] =
            await ethers.getSigners();
        revert = deployments.createFixture(async () => {
            await deployments.fixture();
            ({
                protocolGovernance,
                LpIssuerGovernance,
                LpIssuer,
                tokens,
                gatewayNft,
                lpIssuerNft,
            } = await deploySystem({
                adminSigner: admin,
                treasury: await treasury.getAddress(),
                vaultOwnerSigner: deployer,
                strategy: await strategy.getAddress(),
            }));
        });
    });

    beforeEach(async () => {
        await revert();
    });

    describe("::constructor", () => {
        it("passes", async () => {
            expect(
                await deployer.provider?.getCode(LpIssuer.address)
            ).to.not.equal("0x");
        });
    });

    describe("::addSubvault", () => {
        describe("when called not by VaultGovernance", () => {
            it("reverts", async () => {
                await expect(
                    LpIssuer.connect(stranger).addSubvault(42)
                ).to.be.revertedWith(
                    Exceptions.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE
                );
            });
        });
    });

    describe("::vaultGovernance", () => {
        it("returns correct VaultGovernance", async () => {
            expect(await LpIssuer.vaultGovernance()).to.equal(
                LpIssuerGovernance.address
            );
        });
    });

    describe("::vaultTokens", () => {
        it("returns correct vaultTokens", async () => {
            expect(await LpIssuer.vaultTokens()).to.deep.equal(
                tokens.map((token) => token.address)
            );
        });
    });

    describe("::subvaultNft", () => {
        it("returns correct subvaultNft", async () => {
            expect(await LpIssuer.subvaultNft()).to.equal(gatewayNft);
        });
    });

    describe("::deposit", () => {
        beforeEach(async () => {
            for (let i: number = 0; i < tokens.length; i++) {
                await tokens[i].approve(
                    LpIssuer.address,
                    ethers.constants.MaxUint256
                );
            }
        });

        describe("when not initialized", () => {
            it("passes", async () => {
                await expect(LpIssuer.deposit([1, 1], [])).to.not.be.reverted;
                expect(
                    await LpIssuer.balanceOf(await deployer.getAddress())
                ).to.equal(1);
            });
        });
    });

    describe("::withdraw", () => {
        describe("when totalSupply is 0", () => {
            it("reverts", async () => {
                await expect(
                    LpIssuer.withdraw(await deployer.getAddress(), 1, [])
                ).to.be.revertedWith(Exceptions.TOTAL_SUPPLY_IS_ZERO);
            });
        });

        describe("when totalSupply is greater then 0", () => {
            it("passes", async () => {
                await expect(LpIssuer.deposit([1, 1], [])).to.not.be.reverted;
                await expect(
                    LpIssuer.withdraw(await deployer.getAddress(), 1, [])
                ).to.not.be.reverted;
            });
        });
    });
});
