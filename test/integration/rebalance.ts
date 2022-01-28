import hre from "hardhat";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import { abi as INonfungiblePositionManager } from "@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol/INonfungiblePositionManager.json";
import { BigNumber } from "@ethersproject/bignumber";
import { mint, sleep, mintUniV3Position_USDC_WETH } from "../library/Helpers";
import { contract } from "../library/setup";
import { ERC20RootVault } from "../types/ERC20RootVault";
import { UniV3Vault } from "../types/UniV3Vault";
import { ERC20Vault } from "../types/ERC20Vault";
import { setupVault, combineVaults } from "../../deploy/0000_utils";
import { expect } from "chai";
import { Contract } from "@ethersproject/contracts";

type CustomContext = {
    erc20Vault: ERC20Vault;
    uniV3Vault: UniV3Vault;
    positionManager: Contract;
};

type DeployOptions = {};

contract<ERC20RootVault, DeployOptions, CustomContext>(
    "Integration__UniV3_ERC20_rebalance",
    function () {
        const uniV3PoolFee = 3000;

        before(async () => {
            this.deploymentFixture = deployments.createFixture(
                async (_, __?: DeployOptions) => {
                    const { read } = deployments;

                    const { uniswapV3PositionManager } =
                        await getNamedAccounts();

                    const tokens = [this.weth.address, this.usdc.address]
                        .map((t) => t.toLowerCase())
                        .sort();
                    const startNft =
                        (
                            await read("VaultRegistry", "vaultsCount")
                        ).toNumber() + 1;

                    let uniV3VaultNft = startNft;
                    let erc20VaultNft = startNft + 1;
                    await setupVault(
                        hre,
                        uniV3VaultNft,
                        "UniV3VaultGovernance",
                        {
                            createVaultArgs: [
                                tokens,
                                this.deployer.address,
                                uniV3PoolFee,
                            ],
                        }
                    );
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
                        [erc20VaultNft, uniV3VaultNft],
                        this.deployer.address,
                        this.deployer.address
                    );
                    const erc20Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        erc20VaultNft
                    );
                    const uniV3Vault = await read(
                        "VaultRegistry",
                        "vaultForNft",
                        uniV3VaultNft
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
                    this.uniV3Vault = await ethers.getContractAt(
                        "UniV3Vault",
                        uniV3Vault
                    );
                    this.positionManager = await ethers.getContractAt(
                        INonfungiblePositionManager,
                        uniswapV3PositionManager
                    );

                    // add depositor
                    await this.subject
                        .connect(this.admin)
                        .addDepositorsToAllowlist([this.deployer.address]);

                    // configure unit prices
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "stageUnitPrice(address,uint256)",
                        this.weth.address,
                        BigNumber.from(10).pow(18)
                    );
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "stageUnitPrice(address,uint256)",
                        this.usdc.address,
                        BigNumber.from(10).pow(18)
                    );
                    await sleep(86400);
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "commitUnitPrice(address)",
                        this.weth.address
                    );
                    await deployments.execute(
                        "ProtocolGovernance",
                        { from: this.admin.address, autoMine: true },
                        "commitUnitPrice(address)",
                        this.usdc.address
                    );

                    await mint(
                        "USDC",
                        this.deployer.address,
                        BigNumber.from(10).pow(6).mul(3000)
                    );
                    await mint(
                        "WETH",
                        this.deployer.address,
                        BigNumber.from(10).pow(18)
                    );

                    await this.weth.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );
                    await this.usdc.approve(
                        this.subject.address,
                        ethers.constants.MaxUint256
                    );

                    return this.subject;
                }
            );
        });

        beforeEach(async () => {
            await this.deploymentFixture();
        });

        describe("rebalance", () => {
            it("initializes uniV3 vault with position nft and increases tvl respectivly", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });

                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result.tokenId
                );
                const uniV3Tvl = await this.uniV3Vault.tvl();
                expect(uniV3Tvl).to.not.contain(0);
                expect(await this.erc20Vault.tvl()).to.deep.equals([
                    [BigNumber.from(0), BigNumber.from(0)],
                    [BigNumber.from(0), BigNumber.from(0)],
                ]);
            });

            it("deposits", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
                await this.subject.deposit(
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    0
                );
                expect(
                    await this.subject.balanceOf(this.deployer.address)
                ).to.deep.equals(BigNumber.from("1000000000000000000"));
            });

            it("pulls univ3 to erc20 and collects earnings", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                console.log(result.tokenId.toString());

                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](
                    this.deployer.address,
                    this.uniV3Vault.address,
                    result.tokenId
                );
                await this.subject.deposit(
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    0
                );
                await this.uniV3Vault.collectEarnings();
                await this.uniV3Vault.pull(
                    this.erc20Vault.address,
                    [this.usdc.address, this.weth.address],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    []
                );
                console.log((await this.erc20Vault.tvl()).toString());
                console.log(
                    "uniV3Vault tvl",
                    (await this.uniV3Vault.tvl()).toString()
                );
            });

            it("replaces univ3 position", async () => {
                const result = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });

                const { deployer, weth, usdc } = await getNamedAccounts();
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](deployer, this.uniV3Vault.address, result.tokenId);
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result.tokenId
                );
                await this.uniV3Vault.pull(
                    this.erc20Vault.address,
                    [usdc, weth],
                    [
                        BigNumber.from(10).pow(6).mul(3000),
                        BigNumber.from(10).pow(18),
                    ],
                    []
                );
                const result2 = await mintUniV3Position_USDC_WETH({
                    fee: uniV3PoolFee,
                    tickLower: -887220,
                    tickUpper: 887220,
                    usdcAmount: BigNumber.from(10).pow(6).mul(3000),
                    wethAmount: BigNumber.from(10).pow(18),
                });
                await this.positionManager.functions[
                    "safeTransferFrom(address,address,uint256)"
                ](deployer, this.uniV3Vault.address, result2.tokenId);
                expect(await this.uniV3Vault.uniV3Nft()).to.deep.equal(
                    result2.tokenId
                );
            });
        });
    }
);
