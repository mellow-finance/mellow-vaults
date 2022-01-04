import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Assertion } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Context, Suite } from "mocha";
import { equals, sortBy } from "ramda";
import { addSigner, toObject } from "./Helpers";
import {
    AaveVaultGovernance,
    ERC20,
    ERC20VaultGovernance,
    ERC20RootVaultGovernance,
    ProtocolGovernance,
    UniV3VaultGovernance,
    VaultRegistry,
    YearnVaultGovernance,
    YearnVault,
    ERC20Vault,
    AaveVault,
    UniV3Vault,
    ERC20RootVault,
} from "../types";

export type TestContext<T, F> = Suite & {
    subject: T;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    yearnVaultGovernance: YearnVaultGovernance;
    yearnVaultSingleton: YearnVault;
    erc20VaultGovernance: ERC20VaultGovernance;
    erc20VaultSingleton: ERC20Vault;
    aaveVaultGovernance: AaveVaultGovernance;
    aaveVaultSingleton: AaveVault;
    uniV3VaultGovernance: UniV3VaultGovernance;
    uniV3VaultSingleton: UniV3Vault;
    erc20RootVaultGovernance: ERC20RootVaultGovernance;
    erc20RootVaultSingleton: ERC20RootVault;

    usdc: ERC20;
    weth: ERC20;
    wbtc: ERC20;
    tokens: ERC20[];
    deployer: SignerWithAddress;
    admin: SignerWithAddress;
    mStrategyAdmin: SignerWithAddress;
    startTimestamp: number;
    deploymentFixture: (x?: F) => Promise<T>;
    governanceDelay: number;
    [key: string]: any;
};

export async function setupDefaultContext<T, F>(this: TestContext<T, F>) {
    await deployments.fixture();
    this.vaultRegistry = await ethers.getContract("VaultRegistry");
    this.protocolGovernance = await ethers.getContract("ProtocolGovernance");
    this.yearnVaultGovernance = await ethers.getContract(
        "YearnVaultGovernance"
    );
    this.yearnVaultSingleton = await ethers.getContract("YearnVault");

    this.erc20VaultGovernance = await ethers.getContract(
        "ERC20VaultGovernance"
    );
    this.erc20VaultSingleton = await ethers.getContract("ERC20Vault");

    this.aaveVaultGovernance = await ethers.getContract("AaveVaultGovernance");
    this.aaveVaultSingleton = await ethers.getContract("AaveVault");
    this.uniV3VaultGovernance = await ethers.getContract(
        "UniV3VaultGovernance"
    );
    this.uniV3VaultSingleton = await ethers.getContract("UniV3Vault");

    this.erc20RootVaultGovernance = await ethers.getContract(
        "ERC20RootVaultGovernance"
    );
    this.erc20RootVaultSingleton = await ethers.getContract("ERC20RootVault");

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
    this.tokens = sortBy(
        (c: ERC20) => c.address.toLowerCase(),
        [this.usdc, this.weth, this.wbtc]
    );
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
            expected,
            actual,
            true
        );
    }
);
