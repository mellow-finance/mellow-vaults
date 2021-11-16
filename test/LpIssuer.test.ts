import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { expect } from "chai";
import { ethers, deployments, getNamedAccounts } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import Exceptions from "./library/Exceptions";
import { LpIssuer, ProtocolGovernance, VaultRegistry } from "./library/Types";

describe("LpIssuer", () => {
    let deployer: SignerWithAddress;
    let lpIssuer: LpIssuer;
    let vaultRegistry: VaultRegistry;
    let protocolGovernance: ProtocolGovernance;
    let lpIsuerNft: number = 5;
    let revert: Function;

    before(async () => {
        const accounts = await getNamedAccounts();
        deployer = await ethers.getSigner(accounts.deployer);
        revert = deployments.createFixture(async () => {
            await deployments.fixture();
            protocolGovernance = await ethers.getContractAt(
                "ProtocolGovernance",
                (
                    await deployments.get("ProtocolGovernance")
                ).address
            );
            const vaultRegistryDeployment = await deployments.get(
                "VaultRegistry"
            );
            vaultRegistry = await ethers.getContractAt(
                "VaultRegistry",
                vaultRegistryDeployment.address
            );
            const lpIssuerAddress = await vaultRegistry.vaultForNft(
                BigNumber.from(lpIsuerNft)
            );
            lpIssuer = await ethers.getContractAt("LpIssuer", lpIssuerAddress);
        });
    });

    beforeEach(async () => {
        await revert();
    });

    describe("::constructor", () => {
        it("passes", async () => {
            console.log(`LpIssuer deployed at ${lpIssuer.address}`);
            console.log("ok!");
        });
    });
});
