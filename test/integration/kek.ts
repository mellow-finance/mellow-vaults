import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    mintUniV3Position_USDC_WETH,
    mintUniV3Position_WBTC_WETH,
    randomAddress,
    withSigner,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault, ERC20Vault, UniV3Vault } from "../types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
} from "../../deploy/0000_utils";
import { ERC20 } from "../library/Types";
import { integrationVaultBehavior } from "../behaviors/integrationVault";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { abi as ISwapRouter } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { UNIV3_VAULT_INTERFACE_ID } from "../library/Constants";
import Exceptions from "../library/Exceptions";

type CustomContext = {};

type DeployOptions = {

};

contract<UniV3Vault, DeployOptions, CustomContext>("Kek", function () {
    const uniV3PoolFee = 3000;

    before(async () => {

        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;
                
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("integratoin test", () => {
        it("works correctly", async () => {
            const lStrategy = await ethers.getContractAt("LStrategy", this.lStrategy.address);
            const lowerVaultAddress = lStrategy.lowerVault();
            const lowerVault = await ethers.getContractAt("IUniV3Vault", lowerVaultAddress);
            const positionManager = await ethers.getContractAt("INonfungiblePositionManager", await lStrategy.positionManager());
            const nft = await lowerVault.uniV3Nft();
            console.log(nft);
            let [, , , , , tickLower, tickUpper, , , , , ] = await positionManager.positions(nft);
            console.log(tickLower);
            console.log(tickUpper);
        });
    });
});