import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import {
    encodeToBytes,
    generateSingleParams,
    randomAddress,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { CurveValidator } from "./types";
import {
    ALLOWED_APPROVE_LIST,
    PermissionIdsLibrary,
} from "../deploy/0000_utils";
import { ValidatorBehaviour } from "./behaviors/validator";
import Exceptions from "./library/Exceptions";
import { randomBytes, randomInt } from "crypto";
import { uint256, uint8 } from "./library/property";

type CustomContext = {};

type DeployOptions = {};

contract<CurveValidator, DeployOptions, CustomContext>(
    "CurveValidator",
    function () {
        const CURVE_EXCHANGE_SELECTOR = "0x3df02124";

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    await deployments.fixture();
                    const { address } = await deployments.get("CurveValidator");
                    this.subject = await ethers.getContractAt(
                        "CurveValidator",
                        address
                    );

                    const vaultTokens = [this.dai.address, this.usdc.address];
                    let vaultOwner = randomAddress();
                    const { vault } = await this.erc20VaultGovernance
                        .connect(this.admin)
                        .callStatic.createVault(vaultTokens, vaultOwner);
                    await this.erc20VaultGovernance
                        .connect(this.admin)
                        .createVault(vaultTokens, vaultOwner);
                    this.vault = await ethers.getContractAt(
                        "ERC20Vault",
                        vault
                    );
                    this.poolAddress =
                        ALLOWED_APPROVE_LIST["mainnet"]["curve"][0];
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#validate", () => {
            it("succesful validate", async () => {
                await withSigner(this.vault.address, async (signer) => {
                    await expect(
                        this.subject
                            .connect(signer)
                            .validate(
                                signer.address,
                                this.poolAddress,
                                randomInt(1, 1000),
                                CURVE_EXCHANGE_SELECTOR,
                                encodeToBytes(
                                    ["int128", "int128", "uint256", "uint256"],
                                    [
                                        generateSingleParams(uint8),
                                        0,
                                        generateSingleParams(uint256),
                                        generateSingleParams(uint256),
                                    ]
                                )
                            )
                    ).to.not.be.reverted;
                });
            });
            describe("edge cases:", async () => {
                describe("if selector is not exchange", async () => {
                    it(`reverts with ${Exceptions.INVALID_SELECTOR}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        signer.address,
                                        randomAddress(),
                                        randomInt(1, 1000),
                                        randomBytes(4),
                                        randomBytes(randomInt(32))
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_SELECTOR);
                        });
                    });
                });

                describe("if token ids are equal", async () => {
                    it(`reverts with ${Exceptions.INVALID_VALUE}`, async () => {
                        await withSigner(randomAddress(), async (signer) => {
                            let amount = generateSingleParams(uint8);
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        signer.address,
                                        randomAddress(),
                                        randomInt(1, 1000),
                                        CURVE_EXCHANGE_SELECTOR,
                                        encodeToBytes(
                                            [
                                                "int128",
                                                "int128",
                                                "uint256",
                                                "uint256",
                                            ],
                                            [
                                                amount,
                                                amount,
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint256),
                                            ]
                                        )
                                    )
                            ).to.be.revertedWith(Exceptions.INVALID_VALUE);
                        });
                    });
                });

                describe("if not a vault token", async () => {
                    it(`reverts with ${Exceptions.INVALID_TOKEN}`, async () => {
                        await withSigner(
                            this.erc20VaultSingleton.address,
                            async (signer) => {
                                await expect(
                                    this.subject
                                        .connect(signer)
                                        .validate(
                                            signer.address,
                                            this.poolAddress,
                                            randomInt(1, 1000),
                                            CURVE_EXCHANGE_SELECTOR,
                                            encodeToBytes(
                                                [
                                                    "int128",
                                                    "int128",
                                                    "uint256",
                                                    "uint256",
                                                ],
                                                [
                                                    generateSingleParams(uint8),
                                                    0,
                                                    generateSingleParams(
                                                        uint256
                                                    ),
                                                    generateSingleParams(
                                                        uint256
                                                    ),
                                                ]
                                            )
                                        )
                                ).to.be.revertedWith(Exceptions.INVALID_TOKEN);
                            }
                        );
                    });
                });

                describe("if pool has no approve permission", async () => {
                    it(`reverts with ${Exceptions.FORBIDDEN}`, async () => {
                        await this.protocolGovernance
                            .connect(this.admin)
                            .revokePermissions(this.poolAddress, [
                                PermissionIdsLibrary.ERC20_APPROVE,
                            ]);
                        await withSigner(this.vault.address, async (signer) => {
                            await expect(
                                this.subject
                                    .connect(signer)
                                    .validate(
                                        signer.address,
                                        this.poolAddress,
                                        randomInt(1, 1000),
                                        CURVE_EXCHANGE_SELECTOR,
                                        encodeToBytes(
                                            [
                                                "int128",
                                                "int128",
                                                "uint256",
                                                "uint256",
                                            ],
                                            [
                                                generateSingleParams(uint8),
                                                0,
                                                generateSingleParams(uint256),
                                                generateSingleParams(uint256),
                                            ]
                                        )
                                    )
                            ).to.be.revertedWith(Exceptions.FORBIDDEN);
                        });
                    });
                });
            });
        });

        ValidatorBehaviour.call(this, {});
    }
);
