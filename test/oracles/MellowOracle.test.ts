import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { expect } from "chai";
import { MellowOracle } from "../types";

import {
    UNIV2_ORACLE_INTERFACE_ID,
    ORACLE_INTERFACE_ID,
} from "../library/Constants";

type CustomContext = {
    mellowOracle: MellowOracle;
};

type DeployOptions = {
    isActiveUniV2Oracle: boolean;
    isActiveUniV3Oracle: boolean;
    isActiveChainlinkOracle: boolean;
};

const DEFAULT_DEPLOY_PARAMS: DeployOptions = {
    isActiveChainlinkOracle: true,
    isActiveUniV2Oracle: false,
    isActiveUniV3Oracle: true,
};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "MellowOracle",
    function () {
        const deployMellowOracle = async (options: DeployOptions) => {
            const { deployments, getNamedAccounts } = hre;
            const { deploy, get } = deployments;
            const { deployer } = await getNamedAccounts();

            var chainlinkOracleAddress = ethers.constants.AddressZero;
            var univ3OracleAddress = ethers.constants.AddressZero;
            var univ2OracleAddress = ethers.constants.AddressZero;

            if (options) {
                if (options.isActiveChainlinkOracle) {
                    chainlinkOracleAddress = (await get("ChainlinkOracle"))
                        .address;
                }

                if (options.isActiveUniV2Oracle) {
                    univ2OracleAddress = (await get("UniV2Oracle")).address;
                }

                if (options.isActiveUniV3Oracle) {
                    univ3OracleAddress = (await get("UniV3Oracle")).address;
                }
            }

            await deploy("MellowOracle", {
                from: deployer,
                args: [
                    univ2OracleAddress,
                    univ3OracleAddress,
                    chainlinkOracleAddress,
                ],
                log: true,
                autoMine: true,
            });

            this.mellowOracle = await ethers.getContract("MellowOracle");
        };

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, options?: DeployOptions) => {
                    deployMellowOracle(
                        options ? options : DEFAULT_DEPLOY_PARAMS
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture(DEFAULT_DEPLOY_PARAMS);
        });

        describe("#contructor", () => {
            it("deploys a new contract", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.mellowOracle.address
                );
            });

            it("initializes name", async () => {
                expect("MellowOracle").to.be.eq(
                    await this.mellowOracle.contractName()
                );
            });

            it("initializes version", async () => {
                expect("1.0.0").to.be.eq(
                    await this.mellowOracle.contractVersion()
                );
            });

            it("initializes IUniV3Oracle", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    await this.mellowOracle.univ3Oracle()
                );
            });

            it("initializes IChainlinkOracle", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    await this.mellowOracle.chainlinkOracle()
                );
            });

            describe("edge cases:", () => {
                describe("when creates by default", () => {
                    it("does not initialize IUniV2Oracle", async () => {
                        expect(ethers.constants.AddressZero).to.be.eq(
                            await this.mellowOracle.univ2Oracle()
                        );
                    });
                });
            });
        });

        describe("#supportsInterface", () => {
            it(`returns true for IUniV3Oracle interface (${ORACLE_INTERFACE_ID})`, async () => {
                let isSupported = await this.mellowOracle.supportsInterface(
                    ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.true;
            });

            describe("edge cases:", () => {
                describe("when contract does not support the given interface", () => {
                    it("returns false", async () => {
                        let isSupported =
                            await this.mellowOracle.supportsInterface(
                                UNIV2_ORACLE_INTERFACE_ID
                            );
                        expect(isSupported).to.be.false;
                    });
                });
            });
        });

        describe("#price", () => {
            type TestParameters = {
                opts: DeployOptions;
                name: string;
                size: number;
                mask: number;
            };

            const tests: TestParameters[] = [
                {
                    opts: {
                        isActiveUniV2Oracle: false,
                        isActiveChainlinkOracle: false,
                        isActiveUniV3Oracle: true,
                    },
                    name: "when UniV3Oracle is initialized",
                    size: 4,
                    mask: 30,
                },
                {
                    opts: {
                        isActiveUniV2Oracle: false,
                        isActiveChainlinkOracle: true,
                        isActiveUniV3Oracle: false,
                    },
                    name: "when ChainlinkOracle is initialized",
                    size: 1,
                    mask: 32,
                },
                {
                    opts: {
                        isActiveUniV2Oracle: true,
                        isActiveChainlinkOracle: false,
                        isActiveUniV3Oracle: false,
                    },
                    name: "when UniV2Oracle is initialized",
                    size: 1,
                    mask: 2,
                },
                {
                    opts: {
                        isActiveUniV2Oracle: true,
                        isActiveChainlinkOracle: true,
                        isActiveUniV3Oracle: true,
                    },
                    name: "when MellowOracle is initialized",
                    size: 6,
                    mask: 127,
                },
            ];

            tests.forEach((params) => {
                describe(params.name, () => {
                    it("returns correct response", async () => {
                        await deployMellowOracle(params.opts);
                        const pricesResult = await this.mellowOracle.price(
                            this.usdc.address,
                            this.weth.address,
                            BigNumber.from(params.mask)
                        );

                        const pricesX96 = pricesResult.pricesX96;
                        const safetyIndices = pricesResult.safetyIndices;
                        expect(params.size).to.be.eq(pricesX96.length);
                        expect(params.size).to.be.eq(safetyIndices.length);
                    });
                });
            });

            describe("edge cases:", () => {
                describe("when one of tokens is zero", () => {
                    it("returns empty response", async () => {
                        await deployMellowOracle(DEFAULT_DEPLOY_PARAMS);

                        const pricesResult = await this.mellowOracle.price(
                            ethers.constants.AddressZero,
                            this.weth.address,
                            BigNumber.from(31)
                        );

                        const pricesX96 = pricesResult.pricesX96;
                        const safetyIndices = pricesResult.safetyIndices;
                        expect(pricesX96.length).to.be.eq(0);
                        expect(safetyIndices.length).to.be.eq(0);
                    });
                });
            });
        });
    }
);
