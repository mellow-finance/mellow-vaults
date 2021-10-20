import { expect } from "chai";
import { 
    ethers,
    network,
    deployments
} from "hardhat";
import {
    Signer
} from "ethers";
import { before } from "mocha";
import Exceptions from "./library/Exceptions";
import { deployLpIssuerGovernance, deployProtocolGovernance } from "./library/Deployments";
import { LpIssuerGovernance, ProtocolGovernance, ProtocolGovernance_Params } from "./library/Types";
import { LpIssuerGovernance_constructorArgs } from "./library/Types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";


describe("LpIssuerGovernance", () => {
    let contract: LpIssuerGovernance;
    let protocol: ProtocolGovernance;
    let constructorArgs: LpIssuerGovernance_constructorArgs;
    let timestamp: number;
    let timeout: number;
    let deploymentFixture: Function;
    let deployer: Signer;
    let stranger: Signer;
    let user: Signer;

    before(async () => {
        [deployer, stranger, user] = await ethers.getSigners();
        deploymentFixture = deployments.createFixture(async () => {
            await deployments.fixture();
            protocol = await deployProtocolGovernance();
            constructorArgs = {
                gatewayVault: ethers.constants.AddressZero,
                protocolGovernance: protocol.address
            };
            return deployLpIssuerGovernance({constructorArgs});
        });
    });

    beforeEach(async () => {
        contract = await deploymentFixture();
    });

    describe("constructor", () => {
        it("sets default params", async () => {
            expect(
                await contract.governanceParams()
            ).to.deep.equal([
                constructorArgs.gatewayVault, 
                constructorArgs.protocolGovernance
            ]);
        }); 
    });
});

