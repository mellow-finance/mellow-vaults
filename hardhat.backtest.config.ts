import "hardhat-gas-reporter";
import { HardhatUserConfig } from "hardhat/types";
import defaultConfig from "./hardhat.test.config";
import "./tasks/lstrategy-backtest";

const config: HardhatUserConfig = {
    ...defaultConfig,
    networks: {
        ...defaultConfig.networks,
        hardhat: {
            ...defaultConfig.networks?.hardhat,
            forking: process.env["MAINNET_RPC"]
                ? {
                      url: process.env["MAINNET_RPC"],
                      blockNumber: 14297758,
                  }
                : undefined,
        }
    },
    gasReporter: {
        outputFile: "lstrategy_gas.txt",
        noColors: true,
    },
}

export default config;
