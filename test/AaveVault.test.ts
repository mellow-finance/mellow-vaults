import { expect } from "chai";
import { 
    ethers,
    network
} from "hardhat";
import { 
    ContractFactory, 
    Contract, 
    Signer
} from "ethers";
import Exceptions from "./library/Exceptions";
import { BigNumber } from "@ethersproject/bignumber";
import { 
    AaveToken, 
    AaveVaultFactory,
    AaveVault,
    AaveVaultManager,
} from "./library/Types";
import { deployAaveVaultSystem } from "./library/Deployments";
import { 
    ProtocolGovernance,
    VaultGovernance,
    VaultGovernanceFactory
 } from "./library/Types";

describe("AaveVaultFactory", function() {
    this.timeout(100 * 1000);
    let deployer: Signer;
    let stranger: Signer;
    let treasury: Signer;
    let protocolGovernanceAdmin: Signer;

    let protocolGovernance: ProtocolGovernance;
    let tokens: AaveToken[];
    let AaveVault: AaveVault;
    let AaveVaultManager: AaveVaultManager;
    let AaveVaultFactory: AaveVaultFactory;
    let aaveVaultFactory: AaveVault;

    let nft: number;
    let vaultGovernance: VaultGovernance;
    let vaultGovernanceFactory: VaultGovernanceFactory;

    before(async() => {
        [
            deployer,
            stranger,
            treasury,
            protocolGovernanceAdmin,
        ] = await ethers.getSigners();
        ({
            AaveVault,
            AaveVaultManager,
            AaveVaultFactory,
            vaultGovernance,
            vaultGovernanceFactory,
            protocolGovernance,
            tokens,
            nft
        } = await deployAaveVaultSystem({
            protocolGovernanceAdmin: protocolGovernanceAdmin,
            treasury: await treasury.getAddress(),
            tokensCount: 10, 
            permissionless: true,
            vaultManagerName: "vault manager",
            vaultManagerSymbol: "Aavevm ¯\\_(ツ)_/¯"
        }));
    });

    describe("constructor", () => {
        it("", async () =>  {
        });
    });
});