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
import { deployAaveVaultSystem,
         AaveToken, 
         AaveVaultFactory,
         AaveVault,
         AaveVaultManager,
} from "./library/Fixtures";
import { ProtocolGovernance,
         VaultGovernance,
         VaultGovernanceFactory
 } from "./library/Types";

describe("AaveVaultFactory", () => {
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

    let user1: Signer;
    let user2: Signer;
    let timestamp: number;
    let timeout: number;
    // let params: GovernanceParams;
    // let paramsZero: GovernanceParams;
    // let paramsTimeout: GovernanceParams;
    // let paramsEmpty: GovernanceParams;
    // let paramsDefault: GovernanceParams;
    let defaultGovernanceDelay: number;
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
                vaultManagerSymbol: "Aavevm"
            }));
    });

    describe("constructor", () => {
        it("", async () =>  {
            
        });
    });
});