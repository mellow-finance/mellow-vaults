import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "./plugins/contracts";
import defaultConfig from "./hardhat.config";
import { lens, lensPath, pipe, set } from "ramda";
import { MultiSolcUserConfig, SolcUserConfig } from "hardhat/types";

type HardhatUserConfigWithTypechain = HardhatUserConfig & {
    typechain?: {
        outDir?: string;
        target?: string;
        alwaysGenerateOverloads: boolean;
        externalArtifacts?: string[];
    };
};

const config: HardhatUserConfigWithTypechain = {
    ...defaultConfig,
    networks: {
        ...defaultConfig.networks,
        hardhat: {
            ...(defaultConfig.networks?.hardhat || {}),
            initialBaseFeePerGas: 0,
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        ...defaultConfig.namedAccounts,
        stranger: {
            default: 5,
        },
        treasury: {
            default: 6,
        },
        protocolGovernanceAdmin: {
            default: 7,
        },
        stranger1: {
            default: 8,
        },
        stranger2: {
            default: 9,
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
        outDir: "src/types",
        target: "ethers-v5",
        alwaysGenerateOverloads: false,
        externalArtifacts: ["artifacts/@openzeppelin/*.json"],
    },
};

export default config;
