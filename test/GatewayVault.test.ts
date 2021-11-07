import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { Signer } from "ethers";
import {
    ERC20,
    Vault,
    VaultGovernance,
    ProtocolGovernance,
} from "./library/Types";
import { deployERC20VaultXVaultGovernanceSystem } from "./library/Deployments";

describe("ERC20VaultGovernance", () => {
    const tokensCount = 2;
    let deployer: Signer;
    let admin: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let anotherTreasury: Signer;
    let vaultGovernance: VaultGovernance;
    let protocolGovernance: ProtocolGovernance;
    let vault: Vault;
    let nft: number;
    let tokens: ERC20[];
    let gatewayVault: Vault;
    let gatewayVaultGovernance: VaultGovernance;
    let gatewayNft: number;
    let deployment: Function;

    before(async () => {
        [deployer, admin, stranger, treasury] =
            await ethers.getSigners();
        deployment = deployments.createFixture(async () => {
            await deployments.fixture();
            ({ } =
                await deployERC20VaultXVaultGovernanceSystem({
                    adminSigner: admin,
                    treasury: await treasury.getAddress(),
                    vaultOwnerSigner: deployer,
                    strategy: await stranger.getAddress(),
                }));
        });
    });

    beforeEach(async () => {
        await deployment();
    });

    describe("constructor", () => {
        it("passes", async () => {
        });
    });
});
