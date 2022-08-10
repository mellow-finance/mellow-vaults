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
import "./tasks/lstrategy-slippage";
import { utils } from "ethers";
import { ethers } from "hardhat";

const config: HardhatUserConfig = {
    ...defaultConfig,
    networks: {
        ...defaultConfig.networks,
        hardhat: {
            forking: process.env["OPTIMISM_RPC"]
                ? {
                      url: process.env["OPTIMISM_RPC"],
                      blockNumber: 17000000,
                  }
                : undefined,

            accounts: process.env["MAINNET_DEPLOYER_PK"]
                ? [
                      {
                          privateKey: process.env["MAINNET_DEPLOYER_PK"],
                          balance: (10 ** 20).toString(),
                      },
                  ]
                : undefined,
            initialBaseFeePerGas: 0,
            allowUnlimitedContractSize: true,
        }
    },
    namedAccounts: {
        ...defaultConfig.namedAccounts,
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
        wbtc: {
            default: "0x68f180fcce6836688e9084f035309e29bf0a2095",
        },
        usdc: {
            default: "0x7f5c764cbc14f9669b88837ca1490cca17c31607",
        },
        weth: {
            default: "0x4200000000000000000000000000000000000006",
        },
        dai: {
            default: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1",
        },
        chainlinkEth: {
            default: "0x13e3ee699d1909e989722e753853ae30b17e08c5",
        },
        chainlinkBtc: {
            default: "0xd702dd976fb76fffc2d3963d037dfdae5b04e593",
        },
        chainlinkUsdc: {
            default: "0x16a9fa2fda030272ce99b29cf780dfa30361e0f3",
        },
        wsteth: {
            default: "0x0000000000000000000000000000000000000000",
        },
        aaveLendingPool: {
            default: "0x0000000000000000000000000000000000000000",
        },
        yearnVaultRegistry: {
            default: "0x0000000000000000000000000000000000000000",
        },
        perpVault: {
            default: "0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60",
        },
        clearingHouse: {
            default: "0x82ac2CE43e33683c58BE4cDc40975E73aA50f459",
        },
        accountBalance: {
            default: "0xA7f3FC32043757039d5e13d790EE43edBcBa8b7c",
        },
        vusdcAddress: {
            default: "0xC84Da6c8ec7A57cD10B939E79eaF9d2D17834E04",
        },
        vethAddress: {
            default: "0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB",
        }
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
