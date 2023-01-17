import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "solidity-coverage";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "@typechain/hardhat";
import "./plugins/contracts";
import defaultConfig from "./hardhat.config";
import { lensPath, set } from "ramda";
import { MultiSolcUserConfig, SolcUserConfig } from "hardhat/types";

const config: HardhatUserConfig = {
    ...defaultConfig,
    networks: {
        ...defaultConfig.networks,
        hardhat: {
            forking: process.env["POLYGON_RPC"]
                ? {
                      url: process.env["POLYGON_RPC"],
                      blockNumber: 36000000,
                  }
                : undefined,

            accounts:
                process.env["POLYGON_DEPLOYER_PK"] &&
                process.env["POLYGON_APPROVER_PK"]
                    ? [
                          {
                              privateKey: process.env["POLYGON_DEPLOYER_PK"],
                              balance: (10 ** 20).toString(),
                          },
                          {
                              privateKey: process.env["POLYGON_APPROVER_PK"],
                              balance: (10 ** 20).toString(),
                          },
                      ]
                    : undefined,
            initialBaseFeePerGas: 0,
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
        approver: {
            default: 1,
        },
        admin: {
            hardhat: "0x9a3CB5A473e1055a014B9aE4bc63C21BBb8b82B3",
        },
        mStrategyAdmin: {
            hardhat: "0x1aD91ee08f21bE3dE0BA2ba6918E714dA6B45836",
        },
        mStrategyTreasury: {
            hardhat: "0x52bc44d5378309EE2abF1539BF71dE1b7d7bE3b5",
        },
        protocolTreasury: {
            hardhat: "0x00192Fb10dF37c9FB26829eb2CC623cd1BF599E8",
        },
        test: {
            default: "0x9a3CB5A473e1055a014B9aE4bc63C21BBb8b82B3",
        },
        wbtc: {
            polygon: "0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6",
        },
        usdc: {
            polygon: "0x2791bca1f2de4661ed88a30c99a7a9449aa84174",
        },
        weth: {
            polygon: "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619",
        },
        bob: {
            polygon: "0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B",
        },
        dai: {
            polygon: "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063",
        },
        aaveLendingPool: {
            polygon: "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf",
        },
        uniswapV3Factory: {
            default: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        },
        uniswapV3PositionManager: {
            default: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        },
        uniswapV3Router: {
            default: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        },
        uniswapV2Factory: {
            polygon: "0xc35DADB65012eC5796536bD9864eD8773aBc74C4",
        },
        uniswapV2Router02: {
            polygon: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
        },
        chainlinkEth: {
            polygon: "0xF9680D99D6C9589e2a93a78A04A279e509205945",
        },
        chainlinkBtc: {
            polygon: "0xc907E116054Ad103354f2D350FD2514433D57F6f",
        },
        chainlinkUsdc: {
            polygon: "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7",
        },
        stranger: {
            default: 5,
        },
        treasury: {
            default: 6,
        },
        stranger1: {
            default: 8,
        },
        stranger2: {
            default: 9,
        },
        wbtcRichGuy: {
            default: "0x000af223187a63f3b0bf6fe5a76ddc79e03ccb55",
        },
    },
    solidity: {
        compilers: (
            defaultConfig.solidity as MultiSolcUserConfig
        ).compilers.map((x: SolcUserConfig) =>
            set(
                lensPath(["settings", "optimizer"]),
                {
                    enabled: false,
                    details: {
                        yul: true,
                        yulDetails: {
                            stackAllocation: true,
                        },
                    },
                },
                x
            )
        ),
    },
    typechain: {
        outDir: "test/types",
        target: "ethers-v5",
        alwaysGenerateOverloads: false,
    },
    mocha: {
        timeout: 800000,
        reporter: process.env["REPORTER"],
    },
};

export default config;
