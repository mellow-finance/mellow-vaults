import hre from "hardhat";
import { ethers, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { expect } from "chai";
import {
    MellowOracle,
    MellowOracle__factory,
    UniV2Oracle,
    UniV2Oracle__factory,
} from "../types";

import {
    ERC165_INTERFACE_ID,
    UNIV2_ORACLE_INTERFACE_ID,
    ORACLE_INTERFACE_ID,
} from "../library/Constants";

type CustomContext = {
    mellowOracle: MellowOracle;
    uniV2Oracle: UniV2Oracle;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "MellowOracle",
    function () {
        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { deployments, getNamedAccounts } = hre;
                    const { deploy, get } = deployments;
                    const { deployer } = await getNamedAccounts();
                    const { address: chainlinkOracle } = await get(
                        "ChainlinkOracle"
                    );
                    const { address: univ3Oracle } = await get("UniV3Oracle");
                    await deploy("MellowOracle", {
                        from: deployer,
                        args: [
                            hre.ethers.constants.AddressZero,
                            univ3Oracle,
                            chainlinkOracle,
                        ],
                        log: true,
                        autoMine: true,
                    });

                    this.mellowOracle = await ethers.getContract(
                        "MellowOracle"
                    );

                    this.uniV2Oracle = await ethers.getContract("UniV2Oracle");
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe.only("#contructor", () => {
            it("creates MellowOracle", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    this.mellowOracle.address
                );
            });

            it("initializes MellowOracle name", async () => {
                expect("MellowOracle").to.be.eq(
                    await this.mellowOracle.contractName()
                );
            });

            it("initializes MellowOracle version", async () => {
                expect("1.0.0").to.be.eq(
                    await this.mellowOracle.contractVersion()
                );
            });

            // corresponds to https://github.com/mellow-finance/mellow-vaults/blob/main/deploy/0054_MellowOracle_univ3.ts#L14
            it("does not initialize IUniV2Oracle", async () => {
                expect(ethers.constants.AddressZero).to.be.eq(
                    await this.mellowOracle.univ2Oracle()
                );
            });

            it("initializes IUniV3Oracle ", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    await this.mellowOracle.univ3Oracle()
                );
            });

            it("initializes IChainlinkOracle ", async () => {
                expect(ethers.constants.AddressZero).to.not.eq(
                    await this.mellowOracle.chainlinkOracle()
                );
            });
        });

        describe.only("#supportsInterface", () => {
            it(`returns true for ERC165 interface (${ERC165_INTERFACE_ID})`, async () => {
                let isSupported = await this.mellowOracle.supportsInterface(
                    ERC165_INTERFACE_ID
                );
                expect(isSupported).to.be.true;
            });

            it(`returns true for IUniV3Oracle interface (${ORACLE_INTERFACE_ID})`, async () => {
                let isSupported = await this.mellowOracle.supportsInterface(
                    ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.true;
            });

            it("returns false when contract does not support the given interface", async () => {
                let isSupported = await this.mellowOracle.supportsInterface(
                    UNIV2_ORACLE_INTERFACE_ID
                );
                expect(isSupported).to.be.false;
            });
        });

        describe.only("#price", () => {
            it("empty response if pools index is zero", async () => {
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

            it("non-empty response in full-mask case", async () => {
                const pricesResult = await this.mellowOracle.price(
                    this.usdc.address,
                    this.weth.address,
                    BigNumber.from(63)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(5);
                expect(safetyIndices.length).to.be.eq(5);
            });

            it("non-empty response in full-mask for ChainlinkOracle case", async () => {
                const pricesResult = await this.mellowOracle.price(
                    this.usdc.address,
                    this.weth.address,
                    BigNumber.from(32)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(1);
                expect(safetyIndices.length).to.be.eq(1);
            });

            it("non-empty response in full-mask for UniV3Oracle case", async () => {
                const pricesResult = await this.mellowOracle.price(
                    this.usdc.address,
                    this.weth.address,
                    BigNumber.from(31)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(4);
                expect(safetyIndices.length).to.be.eq(4);
            });

            it("non-empty response in full-mask and activated UniV2Oracle case", async () => {
                const { deployments, getNamedAccounts } = hre;
                const { deploy } = deployments;
                const { deployer } = await getNamedAccounts();

                await deploy("MellowOracle", {
                    from: deployer,
                    args: [
                        this.uniV2Oracle.address,
                        hre.ethers.constants.AddressZero,
                        hre.ethers.constants.AddressZero,
                    ],
                    log: true,
                    autoMine: true,
                });

                this.mellowOracle = await ethers.getContract("MellowOracle");

                const pricesResult = await this.mellowOracle.price(
                    this.usdc.address,
                    this.weth.address,
                    BigNumber.from(31)
                );

                const pricesX96 = pricesResult.pricesX96;
                const safetyIndices = pricesResult.safetyIndices;
                expect(pricesX96.length).to.be.eq(1);
                expect(safetyIndices.length).to.be.eq(1);
            });
        });
    }
);
