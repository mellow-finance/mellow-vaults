import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "ethers";
import Exceptions from "./library/Exceptions";
import { ERC20, LpIssuerGovernance } from "./library/Types";
import { LpIssuer, ProtocolGovernance, VaultRegistry } from "./library/Types";
import { deploySystem } from "./library/Deployments";
import { comparator } from "ramda";
import { randomAddress, withSigner } from "./library/Helpers";

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
    let reset: Function;

    before(async () => {
        [deployer, admin, stranger, treasury, strategy] =
            await ethers.getSigners();
        reset = deployments.createFixture(async () => {
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
        await reset();
    });

    describe("::constructor", () => {
        it("passes", async () => {
            expect(
                await deployer.provider?.getCode(LpIssuer.address)
            ).to.not.equal("0x");
        });

        describe("when tokens not sorted nor unique", () => {
            it("reverts", async () => {
                const contractFactory = await ethers.getContractFactory(
                    "LpIssuer"
                );
                await expect(
                    contractFactory.deploy(
                        ethers.constants.AddressZero,
                        [tokens[1].address, tokens[0].address],
                        "name",
                        "symbol"
                    )
                ).to.be.revertedWith(Exceptions.SORTED_AND_UNIQUE);
            });
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
                await expect(LpIssuer.deposit([10 ** 9, 10 ** 9], [])).to.not.be
                    .reverted;
                expect(
                    await LpIssuer.balanceOf(await deployer.getAddress())
                ).to.equal(10 ** 9);
            });
        });

        describe("when leftovers happen", () => {
            it("returns them", async () => {
                const token0initialBalance = BigNumber.from(
                    await tokens[0].balanceOf(await deployer.getAddress())
                );
                const token1initialBalance = BigNumber.from(
                    await tokens[1].balanceOf(await deployer.getAddress())
                );
                await LpIssuer.deposit([10 ** 9 + 1, 10 ** 9 + 1], []);
                expect(
                    await LpIssuer.balanceOf(await deployer.getAddress())
                ).to.equal(10 ** 9);
                expect(
                    await tokens[0].balanceOf(await deployer.getAddress())
                ).to.equal(token0initialBalance.sub(10 ** 9));
                expect(
                    await tokens[1].balanceOf(await deployer.getAddress())
                ).to.equal(token1initialBalance.sub(10 ** 9));
            });
        });
    });

    describe("::withdraw", () => {
        beforeEach(async () => {
            for (let i: number = 0; i < tokens.length; i++) {
                await tokens[i].approve(
                    LpIssuer.address,
                    ethers.constants.MaxUint256
                );
            }
        });

        describe("when totalSupply is 0", () => {
            it("reverts", async () => {
                await expect(
                    LpIssuer.withdraw(await deployer.getAddress(), 1, [])
                ).to.be.revertedWith(Exceptions.TOTAL_SUPPLY_IS_ZERO);
            });
        });

        describe("when totalSupply is greater then 0", () => {
            it("passes", async () => {
                await LpIssuer.deposit([10 ** 9, 10 ** 9], []);
                await expect(
                    LpIssuer.withdraw(await deployer.getAddress(), 1, [])
                ).to.not.be.reverted;
                expect(
                    await LpIssuer.balanceOf(await deployer.getAddress())
                ).to.equal(10 ** 9 - 1);

                await expect(
                    LpIssuer.withdraw(
                        await deployer.getAddress(),
                        10 ** 9 - 1,
                        []
                    )
                ).to.not.be.reverted;
                expect(
                    await LpIssuer.balanceOf(await deployer.getAddress())
                ).to.equal(0);
            });
        });
    });

    describe("::nft", () => {
        it("returns correct nft", async () => {
            expect(await LpIssuer.nft()).to.equal(lpIssuerNft);
        });
    });

    describe("::initialize", () => {
        describe("when sender is not VaultGovernance", () => {
            it("reverts", async () => {
                await expect(
                    LpIssuer.connect(stranger).initialize(42)
                ).to.be.revertedWith(
                    Exceptions.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE
                );
            });
        });
    });

    describe("onERC721Received", () => {
        it("locks the token for transfer", async () => {
            const { execute, read, get, deploy } = deployments;
            const { stranger, stranger2, weth, deployer } =
                await getNamedAccounts();
            const vault = randomAddress();
            const vaultGovernance = await get("ERC20VaultGovernance");
            await withSigner(vaultGovernance.address, async (s) => {
                const vaultRegistry = await ethers.getContract("VaultRegistry");
                await vaultRegistry.connect(s).registerVault(vault, stranger);
            });
            const nft = await read("VaultRegistry", "vaultsCount");
            const lpGovernance = await get("LpIssuerGovernance");
            const lp = await deploy("LpIssuer", {
                from: deployer,
                args: [lpGovernance.address, [weth], "test", "test"],
            });
            expect(await read("VaultRegistry", "isLocked", nft)).to.be.false;
            await execute(
                "VaultRegistry",
                { from: stranger, autoMine: true },
                "safeTransferFrom(address,address,uint256)",
                stranger,
                lp.address,
                nft
            );
            expect(await read("VaultRegistry", "isLocked", nft)).to.be.true;
        });
        describe("when called not by vault registry", async () => {
            it("reverts", async () => {
                await expect(
                    LpIssuer.onERC721Received(
                        ethers.constants.AddressZero,
                        ethers.constants.AddressZero,
                        1,
                        []
                    )
                ).to.be.revertedWith("NFTVR");
            });
        });
    });
});
