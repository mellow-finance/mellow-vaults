import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Assertion } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Context, Suite } from "mocha";
import { equals, sortBy } from "ramda";
import { addSigner, toObject } from "./Helpers";
import {
    AaveVaultGovernance,
    ERC20Token as ERC20,
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
    MellowOracle,
    MStrategy,
} from "../types";

export interface TestContext<T, F> extends Suite {
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
    mellowOracle: MellowOracle;
    mStrategy: MStrategy;

    usdc: ERC20;
    weth: ERC20;
    wbtc: ERC20;
    dai: ERC20;
    wsteth: ERC20;
    tokens: ERC20[];
    deployer: SignerWithAddress;
    admin: SignerWithAddress;
    mStrategyAdmin: SignerWithAddress;
    test: SignerWithAddress;
    startTimestamp: number;
    deploymentFixture: (x?: F) => Promise<T>;
    governanceDelay: number;
    [key: string]: any;
}

export function contract<T, F, E>(
    title: string,
    f: (this: TestContext<T, F> & E) => void
) {
    describe(title, function (this: Suite) {
        const self = this as TestContext<T, F> & E;
        before(async () => {
            await setupDefaultContext.call<
                TestContext<T, F>,
                [],
                Promise<void>
            >(self);
        });

        f.call(self);
    });
}

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
    this.mellowOracle = await ethers.getContract("MellowOracle");
    const mStrategy: MStrategy | null = await ethers.getContractOrNull(
        "MStrategyYearn"
    );
    if (!mStrategy) {
        this.mStrategy = await ethers.getContract("MStrategyAave");
    } else {
        this.mStrategy = mStrategy;
    }

    const namedAccounts = await getNamedAccounts();
    for (const name of ["deployer", "admin", "mStrategyAdmin", "test"]) {
        const address = namedAccounts[name];
        const signer = await addSigner(address);
        this[name] = signer;
    }
    const { usdc, weth, wbtc, dai, wsteth } = namedAccounts;
    this.usdc = await ethers.getContractAt("ERC20Token", usdc);
    this.weth = await ethers.getContractAt("ERC20Token", weth);
    this.wbtc = await ethers.getContractAt("ERC20Token", wbtc);
    this.dai = await ethers.getContractAt("ERC20Token", dai);
    this.wsteth = await ethers.getContractAt("ERC20Token", wsteth);
    this.tokens = sortBy(
        (c: ERC20) => c.address.toLowerCase(),
        [this.usdc, this.weth, this.wbtc, this.dai, this.wsteth]
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
