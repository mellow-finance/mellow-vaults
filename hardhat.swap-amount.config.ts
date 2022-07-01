import "hardhat-gas-reporter";
import { HardhatUserConfig } from "hardhat/types";
import defaultConfig from "./hardhat.test.config";
import "./tasks/swap-amount";

const config: HardhatUserConfig = {
    ...defaultConfig,
    networks: {
        hardhat: {
            forking: process.env["MAINNET_RPC"]
                ? {
                      url: process.env["MAINNET_RPC"],
                      blockNumber: 13268999,
                  }
                : undefined
        },
    },
};

export default config;
