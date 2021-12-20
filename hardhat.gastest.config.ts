import "hardhat-gas-reporter";
import { HardhatUserConfig } from "hardhat/types";
import defaultConfig from "./hardhat.test.config";

const config: HardhatUserConfig = {
    ...defaultConfig,
    gasReporter: {
        outputFile: "gas.txt",
        noColors: true,
    },
};

export default config;
