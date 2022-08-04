import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import {
    mint,
    sleep,
} from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault, ERC20Vault, PerpVault } from "../types";
import {
    combineVaults,
    setupVault,
} from "../../deploy/0000_utils";

import { abi as IPerpInternalVault } from "../../test/helpers/PerpVaultABI.json";
import { abi as IClearingHouse } from "../../test/helpers/ClearingHouseABI.json";
import { abi as IAccountBalance } from "../../test/helpers/AccountBalanceABI.json";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<PerpVault, DeployOptions, CustomContext>("Optimism__PerpVault", function () {
    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { read } = deployments;

                const { curveRouter } = await getNamedAccounts();
                this.curveRouter = curveRouter;
                this.preparePush = async () => {
                    await sleep(0);
                };

                const tokens = [this.weth.address, this.usdc.address]
                    .map((t) => t.toLowerCase())
                    .sort();

                const startNft =
                    (await read("VaultRegistry", "vaultsCount")).toNumber() + 1;

                let perpVaultNft = startNft;
                let erc20VaultNft = startNft + 1;

                let veth = "0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB";

                await setupVault(hre, perpVaultNft, "PerpVaultGovernance", {
                    createVaultArgs: [this.deployer.address, veth, 10],
                });
                await setupVault(hre, erc20VaultNft, "ERC20VaultGovernance", {
                    createVaultArgs: [tokens, this.deployer.address],
                });

                await combineVaults(
                    hre,
                    erc20VaultNft + 1,
                    [erc20VaultNft, perpVaultNft],
                    this.deployer.address,
                    this.deployer.address
                );
                const erc20Vault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft
                );
                const perpVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    perpVaultNft
                );
                const erc20RootVault = await read(
                    "VaultRegistry",
                    "vaultForNft",
                    erc20VaultNft + 1
                );

                this.erc20Vault = await ethers.getContractAt(
                    "ERC20Vault",
                    erc20Vault
                );

                this.subject = await ethers.getContractAt(
                    "PerpVault",
                    perpVault
                );

                this.erc20RootVault = await ethers.getContractAt(
                    "ERC20RootVault",
                    erc20RootVault
                );
/*
                for (let address of [
                    this.deployer.address,
                    this.subject.address,
                    this.erc20Vault.address,
                ]) {
                    await mint(
                        "USDC",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await mint(
                        "WETH",
                        address,
                        BigNumber.from(10).pow(18).mul(3000)
                    );
                    await this.weth.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        address,
                        ethers.constants.MaxUint256
                    );
                }
*/
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    });

    describe("#tvl", () => {

        it("returns total value locked", async () => {
            
        });
    });

    

});
