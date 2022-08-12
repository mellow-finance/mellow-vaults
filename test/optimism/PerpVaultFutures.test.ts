import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { BigNumber } from "@ethersproject/bignumber";
import { encodeToBytes, mint, sleep } from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault, ERC20Vault, PerpFuturesVault } from "../types";
import { combineVaults, setupVault } from "../../deploy/0000_utils";

import { abi as IPerpInternalVault } from "../helpers/PerpVaultABI.json";
import { pre } from "fast-check";
import { expect } from "chai";
import { uint256 } from "../library/property";

type CustomContext = {
    erc20Vault: ERC20Vault;
    erc20RootVault: ERC20RootVault;
    curveRouter: string;
    preparePush: () => any;
};

type DeployOptions = {};

contract<PerpFuturesVault, DeployOptions, CustomContext>(
    "Optimism__PerpFuturesVault",
    function () {
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

                    const tokens = [this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();

                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let perpVaultNft = startNft;
                    let erc20VaultNft = startNft + 1;

                    let veth = "0x8C835DFaA34e2AE61775e80EE29E2c724c6AE2BB";
                    this.leverage = 4;

                    await setupVault(hre, perpVaultNft, "PerpVaultGovernance", {
                        createVaultArgs: [
                            this.deployer.address,
                            veth,
                            BigNumber.from(10).pow(9).mul(this.leverage),
                            true,
                        ],
                    });
                    await setupVault(
                        hre,
                        erc20VaultNft,
                        "ERC20VaultGovernance",
                        {
                            createVaultArgs: [tokens, this.deployer.address],
                        }
                    );

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
                        "PerpFuturesVault",
                        perpVault
                    );

                    this.erc20RootVault = await ethers.getContractAt(
                        "ERC20RootVault",
                        erc20RootVault
                    );

                    const contract = await ethers.getContractAt(
                        "IERC20",
                        this.usdc.address
                    );

                    for (let address of [this.deployer.address]) {
                        const prevBalance = await contract.balanceOf(address);
                        await mint(
                            "OUSDC",
                            address,
                            BigNumber.from(10).pow(6).mul(3000)
                        );
                        await this.usdc.approve(
                            address,
                            ethers.constants.MaxUint256
                        );
                        const newBalance = await contract.balanceOf(address);
                        expect(prevBalance).to.be.lt(newBalance);
                    }

                    this.isClose = async(x: BigNumber, y: BigNumber) => {
                        const delta = x.sub(y).abs();
                        const max = x.gt(y) ? x : y;
                        return (max > delta.mul(1000));
                    }

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("#tvl", () => {
            
            it("zero tvl when nothing is done", async () => {
                const tvl = await this.subject.tvl();
                expect(tvl[0][0]).to.be.eq(BigNumber.from(0));
            });

            it("tvl equals to pure capital", async () => {
                await mint(
                    "OUSDC",
                    this.subject.address,
                    BigNumber.from(10).pow(6).mul(10)
                );

                await this.subject.push(
                    [this.usdc.address],
                    [BigNumber.from(10).pow(6).mul(4)],
                    encodeToBytes(["uint256", "uint256"], [ethers.constants.MaxUint256, 0])
                );

                let tvl = await this.subject.tvl();
                const W = await this.subject.getPositionValue();

                expect(W).to.be.gt(0);

                let expected = BigNumber.from(10).pow(6).mul(4).mul(this.leverage).mul(999).div(1000) //minus trade fees 0.1%
                let isSpotClose = (await this.isClose(expected, tvl[0][0])) || (await this.isClose(expected, tvl[1][0]));

                expect(isSpotClose).to.be.true;

                await this.subject.push(
                    [this.usdc.address],
                    [BigNumber.from(10).pow(6).mul(2)],
                    encodeToBytes(["uint256", "uint256"], [ethers.constants.MaxUint256, 0])
                );
                
                tvl = await this.subject.tvl();
                expected = BigNumber.from(10).pow(6).mul(6).mul(this.leverage).mul(999).div(1000) //minus trade fees 0.1%
                isSpotClose = (await this.isClose(expected, tvl[0][0])) || (await this.isClose(expected, tvl[1][0]));

                expect(isSpotClose).to.be.true;
                
            });
        });
    }
);
