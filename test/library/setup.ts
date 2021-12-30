import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Assertion } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Context, Suite } from "mocha";
import { equals, sortBy } from "ramda";
import { addSigner, toObject } from "./Helpers";
import {
    AaveVaultFactory,
    AaveVaultGovernance,
    ERC20,
    ERC20VaultFactory,
    ERC20VaultGovernance,
    ERC20RootVaultFactory,
    ERC20RootVaultGovernance,
    ProtocolGovernance,
    UniV3VaultFactory,
    UniV3VaultGovernance,
    VaultRegistry,
    YearnVaultFactory,
    YearnVaultGovernance,
} from "../types";

export type TestContext<T, F> = Suite & {
    subject: T;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    yearnVaultGovernance: YearnVaultGovernance;
    erc20VaultGovernance: ERC20VaultGovernance;
    aaveVaultGovernance: AaveVaultGovernance;
    uniV3VaultGovernance: UniV3VaultGovernance;
    erc20RootVaultGovernance: ERC20RootVaultGovernance;
    yearnVaultFactory: YearnVaultFactory;
    erc20VaultFactory: ERC20VaultFactory;
    aaveVaultFactory: AaveVaultFactory;
    uniV3VaultFactory: UniV3VaultFactory;
    erc20RootVaultFactory: ERC20RootVaultFactory;

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
    this.erc20VaultGovernance = await ethers.getContract(
        "ERC20VaultGovernance"
    );
    this.aaveVaultGovernance = await ethers.getContract("AaveVaultGovernance");
    this.uniV3VaultGovernance = await ethers.getContract(
        "UniV3VaultGovernance"
    );
    this.erc20RootVaultGovernance = await ethers.getContract(
        "ERC20RootVaultGovernance"
    );
    this.yearnVaultFactory = await ethers.getContract("YearnVaultFactory");
    this.erc20VaultFactory = await ethers.getContract("ERC20VaultFactory");
    this.aaveVaultFactory = await ethers.getContract("AaveVaultFactory");
    this.uniV3VaultFactory = await ethers.getContract("UniV3VaultFactory");
    this.erc20RootVaultFactory = await ethers.getContract(
        "ERC20RootVaultFactory"
    );

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
