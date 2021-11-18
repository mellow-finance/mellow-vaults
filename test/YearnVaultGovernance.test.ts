import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
} from "./library/Types";
import { deploySubVaultSystem } from "./library/Deployments";
import { sleep } from "./library/Helpers";
import { Contract } from "hardhat/internal/hardhat-network/stack-traces/model";

describe("YearnVaultGovernance", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let vaultGovernance: Contract;
    let deploymentFixture: Function;

    before(async () => {
        [deployer, admin, stranger] = await ethers.getSigners();

        // deploymentFixture = deployments.createFixture(async () => {
        //     await deployments.fixture();
        //     const { execute, read } = deployments;
        //     const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
        //     await execute(
        //         "ProtocolGovernance",
        //         {
        //             from: deployer.address,
        //             log: true,
        //             autoMine: true,
        //         },
        //         "grantRole"
        //     );
        // });
    });

    beforeEach(async () => {
        await deploymentFixture();
    });
});
