import hre from "hardhat";
import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    randomAddress,
    sleep,
    withSigner,
} from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20RootVault, ERC20Vault, BobOracle } from "./types";
import {
    combineVaults,
    PermissionIdsLibrary,
    setupVault,
    TRANSACTION_GAS_LIMITS,
} from "../deploy/0000_utils";
import { integrationVaultBehavior } from "./behaviors/integrationVault";
import {
    AAVE_VAULT_INTERFACE_ID,
    INTEGRATION_VAULT_INTERFACE_ID,
} from "./library/Constants";
import Exceptions from "./library/Exceptions";
import { timeStamp } from "console";
import { uint256 } from "./library/property";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<BobOracle, DeployOptions, CustomContext>("BobOracle", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { deploy } = deployments;
                const { deployer } = await getNamedAccounts();
                await deploy("BobOracle", {
                    from: deployer,
                    args: [
                        "0xC0D19f4FAE83EB51B2adb59EB649c7BC2b19B2f6",
                        "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6",
                    ],
                    log: true,
                    autoMine: true,
                    ...TRANSACTION_GAS_LIMITS,
                });
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe.only("#latestRoundData", () => {
        it("#check correctness", async () => {
            console.log((await this.subject.latestRoundData()).answer);
        });
    });
});
