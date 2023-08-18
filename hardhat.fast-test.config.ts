import "hardhat-gas-reporter";
import { HardhatUserConfig } from "hardhat/types";
import defaultConfig from "./hardhat.test.config";

const config: HardhatUserConfig = {
    ...defaultConfig,
    mocha: {
        timeout: 800000,
        reporter: process.env["REPORTER"],
        forbidOnly: true,
        grep: "^(?!.*(Integration__))",
    },
    paths: {
        tests: "./test/",
        sources: "./src/",
    },
};

export default config;
