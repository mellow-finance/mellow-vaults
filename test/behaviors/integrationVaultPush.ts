import { IntegrationVaultContext } from "./integrationVault";
import { BigNumber, Contract } from "ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import Exceptions from "../library/Exceptions";
import { encodeToBytes } from "../library/Helpers";

export function integrationVaultPushBehavior<S extends Contract>(
    this: IntegrationVaultContext<S, {}>
) {
    it("emits Push event", async () => {
        await expect(
            this.pushFunction(
                ...this.prefixArgs,
                [this.usdc.address],
                [BigNumber.from(1)],
                []
            )
        ).to.emit(this.subject, "Push");
    });
    it("pushes tokens to the underlying protocol", async () => {
        await this.preparePush();
        const args = [
            ...this.prefixArgs,
            [this.usdc.address, this.weth.address],
            [
                BigNumber.from(10).pow(6).mul(3000),
                BigNumber.from(10).pow(18).mul(1),
            ],
            [],
        ];
        const amounts = await this.staticCallPushFunction(...args);
        await this.pushFunction(...args);
        expect(BigNumber.from(amounts[0]).gt(0)).to.be.true;
        expect(BigNumber.from(amounts[1]).gt(0)).to.be.true;
    });

    describe("edge cases", () => {
        describe("when vault's nft is 0", () => {
            it(`reverts with ${Exceptions.INIT}`, async () => {
                await ethers.provider.send("hardhat_setStorageAt", [
                    this.subject.address,
                    "0x4", // address of _nft
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                ]);
                await expect(
                    this.pushFunction(
                        ...this.prefixArgs,
                        [this.usdc.address],
                        [BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INIT);
            });
        });
        describe("when owner's nft is 0", () => {
            it(`reverts with ${Exceptions.NOT_FOUND}`, async () => {
                let address = `0x${this.erc20RootVault.address
                    .substr(2)
                    .padStart(64, "0")}`;
                await ethers.provider.send("hardhat_setStorageAt", [
                    this.vaultRegistry.address,
                    ethers.utils.keccak256(
                        encodeToBytes(
                            ["bytes32", "uint256"],
                            [address, BigNumber.from(10)]
                        )
                    ), // setting _nftIndex[this.erc20RootVault.address] = 0
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                ]);
                await expect(
                    this.pushFunction(
                        ...this.prefixArgs,
                        [this.usdc.address],
                        [BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.NOT_FOUND);
            });
        });
        describe("when tokens and tokenAmounts lengths do not match", () => {
            it("reverts", async () => {
                await expect(
                    this.pushFunction(
                        ...this.prefixArgs,
                        [this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.reverted;
            });
        });
        describe("when tokens are not sorted", () => {
            it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                await expect(
                    this.pushFunction(
                        ...this.prefixArgs,
                        [this.weth.address, this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
        });
        describe("when tokens are not unique", () => {
            it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                await expect(
                    this.pushFunction(
                        ...this.prefixArgs,
                        [this.usdc.address, this.usdc.address],
                        [BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
        });
        describe("when tokens not sorted nor unique", () => {
            it(`reverts with ${Exceptions.INVARIANT}`, async () => {
                await expect(
                    this.pushFunction(
                        ...this.prefixArgs,
                        [
                            this.weth.address,
                            this.usdc.address,
                            this.weth.address,
                        ],
                        [
                            BigNumber.from(1),
                            BigNumber.from(1),
                            BigNumber.from(1),
                        ],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
        });
    });
}
