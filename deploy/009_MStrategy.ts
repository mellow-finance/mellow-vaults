import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import "@nomiclabs/hardhat-ethers";
import "hardhat-deploy";
import { equals } from "ramda";

const setupVault = async (
    hre: HardhatRuntimeEnvironment,
    vaultNft: number,
    startNft: number,
    contractName: string,
    deployOptions: any[],
    delayedStrategyParams: { strategyTreasury: string; [key: string]: any },
    strategyParams?: { [key: string]: any }
) => {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read } = deployments;
    const { deployer } = await getNamedAccounts();
    if (startNft <= vaultNft) {
        log(`Deploying ${contractName.replace("Governance", "")}...`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "deployVault",
            ...deployOptions
        );
        log(`Done, nft = ${vaultNft}`);
    } else {
        log(
            `${contractName.replace(
                "Governance",
                ""
            )} with nft = ${vaultNft} already deployed`
        );
    }

    if (strategyParams) {
        const currentParams = await read(
            contractName,
            "strategyParams",
            vaultNft
        );

        if (!equals(strategyParams, currentParams)) {
            log(`Setting Strategy params for ${contractName}`);
            await execute(
                contractName,
                {
                    from: deployer,
                    log: true,
                    autoMine: true,
                },
                "setStrategyParams",
                vaultNft,
                strategyParams
            );
        }
    }
    let strategyTreasury;
    try {
        const data = await read(
            contractName,
            "delayedStrategyParams",
            vaultNft
        );
        strategyTreasury = data.strategyTreasury;
    } catch {
        return;
    }

    if (strategyTreasury !== delayedStrategyParams.strategyTreasury) {
        log(`Setting delayed strategy params for ${contractName}`);
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "stageDelayedStrategyParams",
            vaultNft,
            delayedStrategyParams
        );
        await execute(
            contractName,
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "commitDelayedStrategyParams",
            vaultNft
        );
    }
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { log, execute, read, get } = deployments;
    const { deployer, mStrategyTreasury, weth, wbtc } =
        await getNamedAccounts();
    const gatewayVaultGovernance = await get("GatewayVaultGovernance");
    const lpIssuerVaultGovernance = await get("LpIssuerGovernance");

    const tokens = [weth, wbtc].map((t) => t.toLowerCase()).sort();
    const startNft =
        (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;
    const coder = hre.ethers.utils.defaultAbiCoder;
    let aaveVaultNft = 1;
    let uniV3VaultNft = 2;
    let erc20VaultNft = 3;
    let gatewayVaultNft = 4;
    let lpIssuerNft = 5;
    await setupVault(
        hre,
        aaveVaultNft,
        startNft,
        "AaveVaultGovernance",
        [tokens, [], deployer],
        { strategyTreasury: mStrategyTreasury }
    );
    await setupVault(
        hre,
        uniV3VaultNft,
        startNft,
        "UniV3VaultGovernance",
        [tokens, coder.encode(["uint256"], [3000]), deployer],
        { strategyTreasury: mStrategyTreasury }
    );
    await setupVault(
        hre,
        erc20VaultNft,
        startNft,
        "ERC20VaultGovernance",
        [tokens, [], deployer],
        { strategyTreasury: mStrategyTreasury }
    );

    const approvedGw = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        gatewayVaultGovernance.address
    );
    const approvedIssuer = await read(
        "VaultRegistry",
        "isApprovedForAll",
        deployer,
        lpIssuerVaultGovernance.address
    );
    if (!approvedGw) {
        log("Approving gateway vault governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "setApprovalForAll",
            gatewayVaultGovernance.address,
            true
        );
    }
    if (!approvedIssuer) {
        log("Approving lp issuer governance");
        await execute(
            "VaultRegistry",
            {
                from: deployer,
                log: true,
                autoMine: true,
            },
            "setApprovalForAll",
            lpIssuerVaultGovernance.address,
            true
        );
    }
    await setupVault(
        hre,
        gatewayVaultNft,
        startNft,
        "GatewayVaultGovernance",
        [
            tokens,
            coder.encode(
                ["uint256[]"],
                [[uniV3VaultNft, aaveVaultNft, erc20VaultNft]]
            ),
            deployer,
        ],
        {
            strategyTreasury: mStrategyTreasury,
            redirects: [uniV3VaultNft, erc20VaultNft, erc20VaultNft],
        },
        {
            limits: [
                hre.ethers.constants.MaxUint256,
                hre.ethers.constants.MaxUint256,
            ],
        }
    );

    await setupVault(
        hre,
        lpIssuerNft,
        startNft,
        "LpIssuerGovernance",
        [
            tokens,
            coder.encode(
                ["uint256", "string", "string"],
                [gatewayVaultNft, "MStrategy LP Token", "MSLP"]
            ),
            deployer,
        ],
        {
            strategyTreasury: mStrategyTreasury,
        },
        { tokenLimitPerAddress: hre.ethers.constants.MaxUint256 }
    );
};

export default func;
func.tags = ["MStrategy"];
