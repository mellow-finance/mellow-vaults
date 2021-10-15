import { expect } from "chai";
import { ethers } from "hardhat";
import { 
    ContractFactory, 
    Contract, 
    Signer 
} from "ethers";
import Exceptions from "./lib/Exceptions";
import {
    setupERC20VaultFactory,
    setupProtocolGovernance,
    setupVaultManagerGovernance,
    setupERC20Vault
} from "./lib/Fixtures";
import { sleepTo } from "./lib/Helpers";

describe("ERC20Vault", () => {
    let deployer: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let admin: Signer;
    let erc20Vault: Contract;
    let vaultGovernance: Contract;
    let tokens: Contract[];

    before(async () => {
        [
            deployer,
            stranger,
            treasury,
            admin
        ] = await ethers.getSigners();

        [erc20Vault, vaultGovernance, tokens] = await setupERC20Vault({
            params: {
                owner: deployer
            },
            treasury: treasury,
            admin: admin,
            tokensCount: 5,
            calldata: []
        });
    });

    describe("vaultGovernance", async () => {
        it("gets vault governace address", async () => {
            expect(await erc20Vault.vaultGovernance()).to.equal(vaultGovernance.address);
        });
    });
});
