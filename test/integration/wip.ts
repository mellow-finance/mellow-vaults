import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import {
  mint,
  sleep,
  mintUniV3Position_USDC_WETH,
  withFunds,
  withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { pit, uint256, uint64, RUNS, address } from "../library/property";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { UniV3Vault } from "../types/UniV3Vault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";

type CustomContext = {
  erc20Vault: ERC20Vault;
  uniV3Vault: UniV3Vault;
  positionManager: Contract;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
  "Integration__wip",
  function () {
    const uniV3PoolFee = 3000;

    before(async () => {
      this.deploymentFixture = deployments.createFixture(
        async (_, __?: DeployOptions) => {
          const { read } = deployments;

          const { uniswapV3PositionManager } = await getNamedAccounts();

          const tokens = [this.weth.address, this.usdc.address]
            .map((t) => t.toLowerCase())
            .sort();
          const startNft =
            (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

          let uniV3VaultNft = startNft;
          let erc20VaultNft = startNft + 1;
          await setupVault(hre, uniV3VaultNft, "UniV3VaultGovernance", {
            createVaultArgs: [tokens, this.deployer.address, uniV3PoolFee],
          });
          await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
            createVaultArgs: [tokens, this.deployer.address],
          });

          await combineVaults(
            hre,
            erc20VaultNft + 1,
            [erc20VaultNft, uniV3VaultNft],
            this.deployer.address,
            this.deployer.address
          );
          const erc20Vault = await read(
            "VaultRegistry",
            "vaultForNft",
            erc20VaultNft
          );
          const uniV3Vault = await read(
            "VaultRegistry",
            "vaultForNft",
            uniV3VaultNft
          );

          const erc20RootVault = await read(
            "VaultRegistry",
            "vaultForNft",
            erc20VaultNft + 1
          );

          this.subject = await ethers.getContractAt(
            "ERC20RootVault",
            erc20RootVault
          );
          this.erc20Vault = await ethers.getContractAt(
            "ERC20Vault",
            erc20Vault
          );
          this.uniV3Vault = await ethers.getContractAt(
            "UniV3Vault",
            uniV3Vault
          );
          this.positionManager = await ethers.getContractAt(
            INonfungiblePositionManager,
            uniswapV3PositionManager
          );

          // add depositor
          await this.subject
            .connect(this.admin)
            .addDepositorsToAllowlist([this.deployer.address]);

          // configure unit prices
          await deployments.execute(
            "ProtocolGovernance",
            { from: this.admin.address, autoMine: true },
            "stageUnitPrice(address,uint256)",
            this.weth.address,
            BigNumber.from(10).pow(18)
          );
          await deployments.execute(
            "ProtocolGovernance",
            { from: this.admin.address, autoMine: true },
            "stageUnitPrice(address,uint256)",
            this.usdc.address,
            BigNumber.from(10).pow(18)
          );
          await sleep(86400);
          await deployments.execute(
            "ProtocolGovernance",
            { from: this.admin.address, autoMine: true },
            "commitUnitPrice(address)",
            this.weth.address
          );
          await deployments.execute(
            "ProtocolGovernance",
            { from: this.admin.address, autoMine: true },
            "commitUnitPrice(address)",
            this.usdc.address
          );

          await mint(
            "USDC",
            this.deployer.address,
            BigNumber.from(10).pow(6).mul(3000)
          );
          await mint("WETH", this.deployer.address, BigNumber.from(10).pow(18));

          await this.weth.approve(
            this.subject.address,
            ethers.constants.MaxUint256
          );
          await this.usdc.approve(
            this.subject.address,
            ethers.constants.MaxUint256
          );

          return this.subject;
        }
      );
    });

    beforeEach(async () => {
      await this.deploymentFixture();
    });

    describe("when UniV3Vault position is empty", () => {
      let cnt = 0;
      pit(
        "(withdraw o deposit) => tvl() = (0, 0) & balanceOf() = 0",
        { numRuns: RUNS.verylow },
        uint64.filter((x) => x.gt(1000)),
        uint64.filter((x) => x.gt(1000_000_000)),
        async (a0: BigNumber, a1: BigNumber) => {
          console.log(`run no${++cnt}`);
          return await withFunds(
            this.deployer,
            "USDC",
            a0,
            this.subject.address,
            async () => {
              return await withFunds(
                this.deployer,
                "WETH",
                a1,
                this.subject.address,
                async () => {
                  await this.subject.deposit([a0, a1], 0);
                  console.log((await this.subject.tvl()).toString());
                  console.log("return true");
                  return true;
                }
              );
            }
          );
        }
      );
    });
  }
);
