import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Assertion } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Context, Suite } from "mocha";
import { equals } from "ramda";
import { addSigner, toObject } from "./library/Helpers";
import {
    AaveVaultGovernance,
    ERC20,
    ERC20VaultGovernance,
    GatewayVaultGovernance,
    LpIssuerGovernance,
    ProtocolGovernance,
    UniV3VaultGovernance,
    VaultRegistry,
    YearnVaultGovernance,
} from "./types";

export type TestContext = Suite & {
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    yearnVaultGovernance: YearnVaultGovernance;
    erc20VaultGovernance: ERC20VaultGovernance;
    aaveVaultGovernance: AaveVaultGovernance;
    uniV3VaultGovernance: UniV3VaultGovernance;
    gatewayVaultGovernance: GatewayVaultGovernance;
    lpIssuerGovernance: LpIssuerGovernance;
    usdc: ERC20;
    weth: ERC20;
    wbtc: ERC20;
    tokenAddresses: string[];
    deployer: SignerWithAddress;
    admin: SignerWithAddress;
    mStrategyAdmin: SignerWithAddress;
    startTimestamp: number;
    deploymentFixture: Function;
    governanceDelay: number;
    [key: string]: any;
};

export async function setupDefaultContext(this: TestContext) {
    await deployments.fixture();
    this.vaultRegistry = await ethers.getContract("VaultRegistry");
    this.protocolGovernance = await ethers.getContract("ProtocolGovernance");
    this.yearnVaultGovernance = await ethers.getContract(
        "YearnVaultGovernance"
    );
    this.erc20VaultGovernance = await ethers.getContract(
        "ERC20VaultGovernance"
    );
    this.aaveVaultGovernance = await ethers.getContract("AaveVaultGovernance");
    this.uniV3VaultGovernance = await ethers.getContract(
        "UniV3VaultGovernance"
    );
    this.gatewayVaultGovernance = await ethers.getContract(
        "GatewayVaultGovernance"
    );
    this.lpIssuerGovernance = await ethers.getContract("LpIssuerGovernance");
    const namedAccounts = await getNamedAccounts();
    for (const name of ["deployer", "admin", "mStrategyAdmin"]) {
        const address = namedAccounts[name];
        let signer = await ethers.getSignerOrNull(address);
        if (!signer) {
            signer = await addSigner(address);
        }
        // @ts-ignore
        this[name] = signer;
    }
    const { usdc, weth, wbtc } = namedAccounts;
    this.usdc = await ethers.getContractAt("ERC20", usdc);
    this.weth = await ethers.getContractAt("ERC20", weth);
    this.wbtc = await ethers.getContractAt("ERC20", wbtc);
    this.tokenAddresses = [usdc, weth, wbtc]
        .map((x) => x.toLowerCase())
        .sort()
        .map((x) => ethers.utils.getAddress(x));
    this.governanceDelay = (
        await this.protocolGovernance.governanceDelay()
    ).toNumber();
}

declare global {
    namespace Chai {
        interface Assertion {
            equivalent: (value: any, message?: string) => Assertion;
        }
    }
}

Assertion.addMethod(
    "equivalent",
    function (this: Chai.AssertionStatic, that: Object) {
        const expected = toObject(this._obj);
        const actual = toObject(that);
        this.assert(
            equals(expected, actual),
            "Expected #{exp} to be equal #{act}",
            "Expected #{exp} not to be equal #{act}",
            this._obj,
            that,
            true
        );
    }
);
