import hre, {deployments, ethers, getNamedAccounts} from "hardhat";
import {contract} from "./library/setup";
import {ERC20RootVault, ERC20Vault} from "./types";
import {combineVaults, setupVault} from "../deploy/0000_utils";

type CustomContext = {
    erc20Vault: ERC20Vault;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "ERC20RootVault::chargefees",
    function () {
        const uniV3PoolFee = 3000;

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;
                    const { deployer, weth, usdc } = await getNamedAccounts();

                    const tokens = [weth, usdc]
                        .map((t) => t.toLowerCase())
                        .sort();

                    let erc20VaultNft = (
                        await read("VaultRegistry", "vaultsCount")
                    ).toNumber() + 1;

                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, deployer],
                        }
                    );

                    await combineVaults(
                        hre,
                        erc20VaultNft + 1,
                        [erc20VaultNft],
                        deployer,
                        deployer
                    );

                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );

                    const erc20RootVault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft + 1
                    );

                    this.subject = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );
                    this.erc20Vault = await ethers.getContractAt(
                        "ERC20Vault",
                        erc20Vault
                    );
                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe.only("#roflan", () => {
            it("initializes uniV3 vault with position nft", async () => {
                await this.subject.deposit([321], 312);
            });
        });
    }
);
