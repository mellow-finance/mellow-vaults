import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import { config as dotenv } from "dotenv";

dotenv();

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      // blockGasLimit: 0x1ffffffffffff,
    },
    dev: {
      url: "http://localhost:8545",
    },
    kovan: {
      url: process.env["KOVAN_RPC"] || "",
      accounts: [
        process.env["KOVAN_DEPLOYER_PK"] ||
          "",
      ],
      // gasPrice: 20000000000,
    },
    mainnet: {
      url: process.env["MAINNET_RPC"] || "",
      accounts: [
        process.env["MAINNET_DEPLOYER_PK"] ||
          "",
      ],
    },
  },
  namedAccounts: {
    deployer: {
      "mainnet": 0,
      "kovan": 0,
    },
    usdc: {
      "mainnet": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      "kovan": "0x600103d518cC5E8f3319D532eB4e5C268D32e604"
    },
    weth: {
      "mainnet": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      "kovan": "0xd0a1e359811322d97991e03f863a0c30c2cf029c ",
    },
    aaveLendingPool: {
      "mainnet": "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
      "kovan": "0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe",
    },
    uniswapV3Factory: {
      "mainnet": "0x1F98431c8aD98523631AE4a59f267346ea31F984",
      "kovan": "0x74e838ecf981aaef2523aa5b666175da319d8d31",
    },
    uniswapV3PositionManager: {
      "mainnet": "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
      "kovan": "0x815BCC87613315327E04e4A3b7c96a79Ae80760c"
    },
    uniswapV3Router: {
      "mainnet": "0xE592427A0AEce92De3Edee1F18E0157C05861564",
      "kovan": "0x8a0B62Fbcb1B862BbF1ad31c26a72b7b746EdFC1"
    }
  },

  solidity: {
    compilers: [
      {
        version: "0.8.7",
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
  etherscan: {
    apiKey: process.env["ETHERSCAN_TOKEN"],
  },
};

export default config;