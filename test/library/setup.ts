import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { Assertion } from "chai";
import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Context, Suite } from "mocha";
import { equals, sortBy } from "ramda";
import { abi as ICurvePool } from "../helpers/curvePoolABI.json";
import { abi as IWETH } from "../helpers/wethABI.json";
import { abi as IWSTETH } from "../helpers/wstethABI.json";
import { BigNumber } from "@ethersproject/bignumber";
import {
    encodeToBytes,
    mint,
    mintUniV3Position_USDC_WETH,
    mintUniV3Position_WBTC_WETH,
    randomAddress,
    withSigner,
} from "../library/Helpers";
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
    LStrategy,
    VoltzVaultGovernance,
    VoltzVault,
    LPOptimiserStrategy,
    HStrategy,
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
    lStrategy: LStrategy;
    voltzVaultGovernance: VoltzVaultGovernance;
    voltzVaultSingleton: VoltzVault;
    lPOptimiserStrategy: LPOptimiserStrategy;
    hStrategy: HStrategy;

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
    const { deployer, weth, wsteth } = await getNamedAccounts();

    //////////////////////////////////////////////////////////////////////// MINT SMALL AMOUNTS ON THE DEPLOYER ADDRESS
    const smallAmount = BigNumber.from(10).pow(13);

    await mint("WETH", deployer, smallAmount);

    const wethContract = await ethers.getContractAt(IWETH, weth);
    const wstethContract = await ethers.getContractAt(IWSTETH, wsteth);

    const curvePool = await ethers.getContractAt(
        ICurvePool,
        "0xDC24316b9AE028F1497c275EB9192a3Ea0f67022" // address of curve weth-wsteth
    );
    this.curvePool = curvePool;

    const steth = await ethers.getContractAt(
        "ERC20Token",
        "0xae7ab96520de3a18e5e111b5eaab095312d7fe84"
    );

    await wethContract.approve(curvePool.address, ethers.constants.MaxUint256);
    await steth.approve(wstethContract.address, ethers.constants.MaxUint256);

    await wethContract.withdraw(smallAmount.div(2));
    const options = { value: smallAmount.div(2) };
    await curvePool.exchange(
        0,
        1,
        smallAmount.div(2),
        ethers.constants.Zero,
        options
    );
    await wstethContract.wrap(smallAmount.div(2).mul(99).div(100));

    ////////////////////////////////////////////////////////////////////////

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

    this.voltzVaultGovernance = await ethers.getContract(
        "VoltzVaultGovernance"
    );
    this.voltzVaultSingleton = await ethers.getContract("VoltzVault");

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
    this.lStrategy = await ethers.getContract("LStrategy");
    this.lPOptimiserStrategy = await ethers.getContract("LPOptimiserStrategy");

    const hStrategy: HStrategy | null = await ethers.getContractOrNull(
        "HStrategyAave"
    );
    if (!hStrategy) {
        this.hStrategy = await ethers.getContract("HStrategyYearn");
    } else {
        this.hStrategy = hStrategy;
    }

    const namedAccounts = await getNamedAccounts();
    for (const name of ["deployer", "admin", "mStrategyAdmin", "test"]) {
        const address = namedAccounts[name];
        const signer = await addSigner(address);
        this[name] = signer;
    }
    const { usdc, wbtc, dai } = namedAccounts;
    this.usdc = await ethers.getContractAt("ERC20Token", usdc);
    this.weth = await ethers.getContractAt("ERC20Token", weth);
    this.wbtc = await ethers.getContractAt("ERC20Token", wbtc);
    this.dai = await ethers.getContractAt("ERC20Token", dai);
    this.wsteth = await ethers.getContractAt("ERC20Token", wsteth);
    this.tokens = sortBy(
        (c: ERC20) => c.address.toLowerCase(),
        [this.usdc, this.weth, this.wbtc, this.dai]
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
