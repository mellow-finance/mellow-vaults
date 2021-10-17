import { expect } from "chai";
import { ethers } from "hardhat";
import { 
    ContractFactory, 
    Contract, 
    Signer 
} from "ethers";
import Exceptions from "./library/Exceptions";
import {
    deployERC20VaultUniverse,

    // types
    ERC20,
    ERC20Vault,
    ERC20VaultManager,
    ERC20VaultFactory,
    VaultGovernance,
    VaultGovernanceFactory,
    ProtocolGovernance
} from "./library/Fixtures";
import { sleepTo } from "./library/Helpers";

describe("ERC20Vault", function() {
    this.timeout(0);

    describe("when permissionless is set to false", () => {

        let deployer: Signer;
        let stranger: Signer;
        let treasury: Signer;
        let protocolGovernanceAdmin: Signer;
    
        let tokens: ERC20[];
        let erc20Vault: ERC20Vault;
        let erc20VaultManager: ERC20VaultManager;
        let erc20VaultFactory: ERC20VaultFactory;
        let vaultGovernance: VaultGovernance;
        let vaultGovernanceFactory: VaultGovernanceFactory;
        let protocolGovernance: ProtocolGovernance;

        let nft: number;
    
        before(async () => {
            [
                deployer,
                stranger,
                treasury,
                protocolGovernanceAdmin,
            ] = await ethers.getSigners();
            
            ({ 
                erc20Vault, 
                erc20VaultManager, 
                erc20VaultFactory, 
                vaultGovernance, 
                vaultGovernanceFactory, 
                protocolGovernance, 
                nft 
            } = await deployERC20VaultUniverse({
                txParams: {
                    from: deployer
                },
                protocolGovernanceAdmin: await protocolGovernanceAdmin.getAddress(),
                treasury: await treasury.getAddress(),
                tokensCount: 10,
                permissionless: false,
                vaultManagerName: "vault manager ¯\_(ツ)_/¯",
                vaultManagerSymbol: "erc20vm"
            })); // from scratch

        });

        describe("constructor", () => {
            it("works", async () => {
                console.log("really works!");
            });
        });
    });
});
