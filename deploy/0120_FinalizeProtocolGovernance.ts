import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import {
    ALLOWED_APPROVE_LIST,
    ALLOW_ALL_CREATE_VAULT,
    ALLOW_MASK,
    ALL_NETWORKS,
    PermissionIdsLibrary,
    PRIVATE_VAULT,
    WBTC_PRICE,
    USDC_PRICE,
    WETH_PRICE,
    TRANSACTION_GAS_LIMITS
} from "./0000_utils";
import { ethers } from "ethers";
import { deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";

// TODO: refactor this

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read, getOrNull } = deployments;
    const { deployer, admin, protocolTreasury, weth, wbtc, usdc } =
        await getNamedAccounts();
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const delay = await read("ProtocolGovernance", "governanceDelay");
    if (delay > 0) {
        log("Protocol governance is already finalized");
        return;
    }
    log("Creating protocol governance finalizing tx");
    const txDatas: (string | undefined)[] = [];
    await setUnitPrices(hre, txDatas);
    await registerGovernances(hre, txDatas);
    await registerTokens(hre, txDatas);
    await registerExternalProtocols(hre, txDatas);

    if (!ALLOW_ALL_CREATE_VAULT) {
        for (const address of [deployer, admin]) {
            const tx =
                await protocolGovernance.populateTransaction.stagePermissionGrants(
                    address,
                    [PermissionIdsLibrary.CREATE_VAULT]
                );
            txDatas.push(tx.data);
        }
    }
    if (txDatas.length > 0) {
        let tx =
            await protocolGovernance.populateTransaction.commitAllPermissionGrantsSurpassedDelay();
        txDatas.push(tx.data);
        tx =
            await protocolGovernance.populateTransaction.commitAllValidatorsSurpassedDelay();
        txDatas.push(tx.data);
    }
    const params = {
        forceAllowMask: ALLOW_MASK,
        maxTokensPerVault: 10,
        governanceDelay: 86400,
        protocolTreasury,
        withdrawLimit: 200000,
    };
    let tx = await protocolGovernance.populateTransaction.stageParams(
        params
    );
    txDatas.push(tx.data);
    tx = await protocolGovernance.populateTransaction.commitParams();
    txDatas.push(tx.data);

    const adminRole = await read("ProtocolGovernance", "ADMIN_ROLE");
    tx = await protocolGovernance.populateTransaction.grantRole(
        adminRole,
        admin
    );
    txDatas.push(tx.data);
    tx = await protocolGovernance.populateTransaction.renounceRole(
        adminRole,
        deployer
    );
    txDatas.push(tx.data);
    await execute(
        "ProtocolGovernance",
        {
            from: deployer,
            autoMine: true,
            log: true,
            ...TRANSACTION_GAS_LIMITS
        },
        "multicall",
        txDatas
    );
};

async function registerGovernances(
    hre: HardhatRuntimeEnvironment,
    txDatas: (string | undefined)[]
) {
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );

    for (const name of [
        "AaveVaultGovernance",
        "UniV3VaultGovernance",
        "VoltzVaultGovernance",
        "ERC20VaultGovernance",
        "YearnVaultGovernance",
        "ERC20RootVaultGovernance",
        "MellowVaultGovernance",
    ]) {
        const governance = await hre.deployments.getOrNull(name);
        if (!governance) {
            continue;
        }
        const tx =
            await protocolGovernance.populateTransaction.stagePermissionGrants(
                governance.address,
                [PermissionIdsLibrary.REGISTER_VAULT]
            );
        txDatas.push(tx.data);
    }
}

async function registerTokens(
    hre: HardhatRuntimeEnvironment,
    txDatas: (string | undefined)[]
) {
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const erc20Validator = await deployments.get("ERC20Validator");
    const { weth, wbtc, usdc, dai, wsteth } = await hre.getNamedAccounts();
    const tokens = [weth, wbtc, usdc, dai, wsteth].map((t) => t.toLowerCase()).sort();
    for (const token of tokens) {
        if (!token) {
            continue
        }
        let tx =
            await protocolGovernance.populateTransaction.stagePermissionGrants(
                token,
                [
                    PermissionIdsLibrary.ERC20_VAULT_TOKEN,
                    PermissionIdsLibrary.ERC20_TRANSFER,
                ]
            );
        txDatas.push(tx.data);
        tx = await protocolGovernance.populateTransaction.stageValidator(
            token,
            erc20Validator.address
        );
        txDatas.push(tx.data);
    }
}

async function registerExternalProtocols(
    hre: HardhatRuntimeEnvironment,
    txDatas: (string | undefined)[]
) {
    let name = hre.network.name;
    if (name === "hardhat" || name === "localhost") {
        name = "mainnet";
    }
    // @ts-ignore
    const data = ALLOWED_APPROVE_LIST[name];
    if (!data) {
        return;
    }
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );

    for (const key in data) {
        if (key == "erc20") { continue; }
        for (const address of data[key]) {
            let tx =
                await protocolGovernance.populateTransaction.stagePermissionGrants(
                    address,
                    [PermissionIdsLibrary.ERC20_APPROVE]
                );
            txDatas.push(tx.data);
        }
    }
    const validators = {
        uniV3: "UniV3Validator",
        uniV2: "UniV2Validator",
        curve: "CurveValidator",
        erc20: "ERC20Validator",
    };
    for (const key in validators) {
        // @ts-ignore
        const validator = await deployments.getOrNull(validators[key]);
        if (!validator) {
            continue;
        }
        for (const address of data[key]) {
            const tx =
                await protocolGovernance.populateTransaction.stageValidator(
                    address,
                    validator.address
                );
            txDatas.push(tx.data);
        }
    }
}

async function setUnitPrices(
    hre: HardhatRuntimeEnvironment,
    txDatas: (string | undefined)[]
) {
    const protocolGovernance = await hre.ethers.getContract(
        "ProtocolGovernance"
    );
    const { admin, weth, wbtc, usdc, wsteth } =
        await hre.getNamedAccounts();
    const txWETH =
        await protocolGovernance.connect(admin).populateTransaction.stageUnitPrice(
            weth,
            WETH_PRICE
        );
    txDatas.push(txWETH.data);
    if (wsteth) {
        const txWSTETH =
            await protocolGovernance.connect(admin).populateTransaction.stageUnitPrice(
                wsteth,
                WETH_PRICE
            );
        txDatas.push(txWSTETH.data);
    }
    const txWBTC =
        await protocolGovernance.connect(admin).populateTransaction.stageUnitPrice(
            wbtc,
            WBTC_PRICE
        );
    txDatas.push(txWBTC.data);
    const txUSDC =
        await protocolGovernance.connect(admin).populateTransaction.stageUnitPrice(
            usdc,
            USDC_PRICE
        );
    txDatas.push(txUSDC.data);
    const txWETHc = await protocolGovernance.connect(admin).populateTransaction.commitUnitPrice(weth);
    txDatas.push(txWETHc.data);
    if (wsteth) {
        const txWSTETHc = await protocolGovernance.connect(admin).populateTransaction.commitUnitPrice(wsteth);
        txDatas.push(txWSTETHc.data);
    }
    const txWBTCc = await protocolGovernance.connect(admin).populateTransaction.commitUnitPrice(wbtc);
    txDatas.push(txWBTCc.data);
    const txUSDCc = await protocolGovernance.connect(admin).populateTransaction.commitUnitPrice(usdc);
    txDatas.push(txUSDCc.data);
}

export default func;
func.tags = ["Finalize", "core", ...ALL_NETWORKS];
func.dependencies = ["ProtocolGovernance"];
