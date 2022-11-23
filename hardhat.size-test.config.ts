import { HardhatUserConfig } from "hardhat/config";
import "hardhat-contract-sizer";
import "hardhat-contract-sizer";

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.9",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                    evmVersion: "istanbul",
                },
            },
            {
                version: "0.7.6",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                    evmVersion: "istanbul",
                },
            },
        ],
    },
};

export default config;
