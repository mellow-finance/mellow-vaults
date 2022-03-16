// import { BigNumber } from "@ethersproject/bignumber";
// import { expect } from "chai";
// import { getNamedAccounts, ethers, deployments } from "hardhat";
// import { mint, randomAddress, withSigner } from "./library/Helpers";
// import { contract, setupDefaultContext, TestContext } from "./library/setup";
// import {
//     ERC20,
//     ERC20RootVault,
//     IIntegrationVault,
//     VaultRegistry,
// } from "./types";
// import { MStrategy } from "./types/MStrategy";

// contract<MStrategy, {}, {}>("MStrategy", function () {
//     let tokens: string[];
//     let tokenContracts: ERC20[];
//     let vaultId: number = 0;
//     let kind: "Yearn" | "Aave";
//     let erc20RootNft: number;

//     before(async () => {
//         kind = "Yearn";
//         // @ts-ignore
//         erc20RootNft = kind === "Yearn" ? 3 : 6;
//         this.deploymentFixture = deployments.createFixture(async () => {
//             await deployments.fixture();

//             const erc20RootVaultAddress = await this.vaultRegistry.vaultForNft(
//                 erc20RootNft
//             );
//             const erc20RootVault: ERC20RootVault = await ethers.getContractAt(
//                 "ERC20RootVault",
//                 erc20RootVaultAddress
//             );
//             tokens = await erc20RootVault.vaultTokens();
//             const balances = [];
//             tokenContracts = [];
//             for (const token of tokens) {
//                 const c: ERC20 = await ethers.getContractAt(
//                     "ERC20Token",
//                     token
//                 );
//                 tokenContracts.push(c);
//                 balances.push(await c.balanceOf(this.test.address));
//                 await c
//                     .connect(this.test)
//                     .approve(
//                         erc20RootVault.address,
//                         ethers.constants.MaxUint256
//                     );
//             }
//             await erc20RootVault
//                 .connect(this.test)
//                 .deposit([balances[0].div(3), balances[1].div(3).mul(2)], 0);
//             this.subject = await ethers.getContract(`MStrategy${kind}`);
//             return this.subject;
//         });
//     });
//     beforeEach(async () => {
//         await this.deploymentFixture();
//     });

//     xdescribe("shouldRebalance", () => {
//         it("checks if the tokens needs to be rebalanced", async () => {
//             expect(await this.subject.shouldRebalance(vaultId)).to.be.true;
//         });
//         describe("after rebalance", () => {
//             it("returns false", async () => {
//                 const moneyVaultAddress = await this.vaultRegistry.vaultForNft(
//                     erc20RootNft - 2
//                 );
//                 const moneyVault: IIntegrationVault =
//                     await ethers.getContractAt(
//                         "IIntegrationVault",
//                         moneyVaultAddress
//                     );
//                 const erc20VaultAddress = await this.vaultRegistry.vaultForNft(
//                     erc20RootNft - 1
//                 );
//                 const erc20Vault: IIntegrationVault =
//                     await ethers.getContractAt(
//                         "IIntegrationVault",
//                         erc20VaultAddress
//                     );

//                 await this.subject.rebalance(vaultId);

//                 expect(await this.subject.shouldRebalance(vaultId)).to.be.false;
//             });
//         });
//     });
// });

import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, MStrategy } from "./types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import {
    AAVE_VAULT_INTERFACE_ID,
    INTEGRATION_VAULT_INTERFACE_ID,
} from "./library/Constants";
import Exceptions from "./library/Exceptions";
import { RatioParamsStruct } from "./types/MStrategy";
import { OracleParamsStruct } from "./types/MStrategy";
import exp from "constants";
import { add } from "ramda";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
};

type DeployOptions = {};

contract<MStrategy, DeployOptions, CustomContext>("MStrategy", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const {
                    deployer,
                    weth,
                    usdc,
                    uniswapV3Router,
                    uniswapV3Factory,
                    mStrategyAdmin,
                    uniswapV3PositionManager,
                } = await getNamedAccounts();

                const tokens = [weth, usdc].map((x) => x.toLowerCase()).sort();
                const startNft = (await this.vaultRegistry.vaultsCount()).toNumber() + 1;
                let yearnVaultNft = startNft;
                let erc20VaultNft = startNft + 1;
                await setupVault(hre, yearnVaultNft, "YearnVaultGovernance", {
                    createVaultArgs: [tokens, deployer],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, deployer],
                });

                const erc20Vault = await this.vaultRegistry.vaultForNft(erc20VaultNft);
                const moneyVault = await this.vaultRegistry.vaultForNft(yearnVaultNft);

                const params = [tokens, erc20Vault, moneyVault, 3000, mStrategyAdmin];
                const mStrategyName = `MStrategyYearn`;
                await deployments.deploy(mStrategyName, {
                    from: deployer,
                    contract: "MStrategy",
                    args: [uniswapV3PositionManager, uniswapV3Router],
                    log: true,
                    autoMine: true,
                });

                const { address: mStrategyAddress } = await deployments.get(mStrategyName);
                const mStrategy = await hre.ethers.getContractAt(
                    "MStrategy",
                    mStrategyAddress
                );
                console.log(mStrategy);
                console.log(mStrategyAddress);
                const address = await mStrategy.callStatic.createStrategy(...params);
                if (!(await deployments.getOrNull(`${mStrategyName}_WETH_USDC`))) {
                    console.log("null");
                    return this.subject;
                }
                await mStrategy.createStrategy(...params);
                await deployments.save(`${mStrategyName}_WETH_USDC`, {
                    abi: (await deployments.get(mStrategyName)).abi,
                    address,
                });
                const mStrategyWethUsdc: MStrategy = await hre.ethers.getContractAt(
                    mStrategyName,
                    address
                );

                this.subject = mStrategyWethUsdc;

                console.log("Setting Strategy params");

                const oracleParams: OracleParamsStruct = {
                    oracleObservationDelta: 15,
                    maxTickDeviation: 50,
                    maxSlippageD: Math.round(0.1 * 10 ** 9),
                };
                const ratioParams: RatioParamsStruct = {
                    tickMin: 198240 - 5000,
                    tickMax: 198240 + 5000,
                    erc20MoneyRatioD: Math.round(0.1 * 10 ** 9),
                    minTickRebalanceThreshold: 0,
                    tickIncrease: 0,
                    tickNeiborhood: 0,
                };

                await this.subject.setOracleParams(oracleParams);
                await this.subject.setRatioParams(ratioParams);

                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("initialization", () => {
        it("works", async () => {
            expect(this.subject.address).to.not.be.equal(ethers.constants.AddressZero);
        });
    });
});
