import { expect } from "chai";
import {BigNumber, Contract} from "ethers";
import {TestContext} from "../library/setup";
import Exceptions from "../library/Exceptions";
import {randomAddress, withSigner} from "../library/Helpers";

export type IntegrationVaultContext<S extends Contract, F> = TestContext<S, F> & {};

export function integrationVaultBehavior<S extends Contract>(
    this: IntegrationVaultContext<S, {}>, {}: {}
) {
    describe("#push", () => {
        it("emits Push event", async () => {
            await expect(this.subject.push(
                [this.usdc.address], [BigNumber.from(1)], [])
            ).to.emit(this.subject, "Push");
        });
        xit("passes when tokens transferred", async () => {
            const args = [
                this.deployer.address,
                [this.usdc.address, this.weth.address],
                [BigNumber.from(10).pow(6).mul(3000), BigNumber.from(10).pow(18).mul(1)],
                [],
            ];
            const amounts = await this.subject.callStatic.transfer(...args);
            console.log(amounts.toString());
            const tx = await this.subject.transfer(...args);
            await tx.wait();
            expect(amounts).to.deep.equal([BigNumber.from(100 * 10 ** 4)]);
        });

        describe("edge cases", () => {
            it("reverts when tokens and tokenAmounts lengths do not match", async () => {
                await expect(this.subject.push(
                    [this.usdc.address], [BigNumber.from(1), BigNumber.from(1)], []
                )).to.be.revertedWith(Exceptions.INVALID_VALUE);
            });
            it("reverts when tokens are not sorted", async () => {
                await expect(this.subject.push(
                    [this.weth.address, this.usdc.address], [BigNumber.from(1), BigNumber.from(1)], []
                )).to.be.revertedWith(Exceptions.INVARIANT)
            })
            it("reverts when tokens are not unique", async () => {
                await expect(
                    this.subject.push(
                        [this.usdc.address, this.usdc.address], [BigNumber.from(1), BigNumber.from(1)], []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("reverts when tokens not sorted nor unique", async () => {
                await expect(
                    this.subject.push(
                        [this.weth.address, this.usdc.address, this.weth.address],
                        [BigNumber.from(1), BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.usdc.transfer(signer.address, BigNumber.from(1));
                    await this.usdc.connect(signer).approve(this.subject.address, BigNumber.from(1));

                    await expect(this.subject.connect(signer).push(
                        [this.usdc.address], [BigNumber.from(1)], []
                    )).to.not.be.reverted;
                });
            });
        });
    });

    describe("#transferAndPush", () => {
        it("emits Push event", async () => {
            await expect(this.subject.transferAndPush(
                this.deployer.address, [this.usdc.address], [BigNumber.from(1)], [])
            ).to.emit(this.subject, "Push");
        });
        it("reverts when not enough balance", async () => {
            const deployerBalance = await this.usdc.balanceOf(this.deployer.address);
            await expect(this.subject.transferAndPush(
                this.deployer.address, [this.usdc.address], [BigNumber.from(deployerBalance).mul(2)], []
            )).to.be.revertedWith("ERC20: transfer amount exceeds balance");
        });

        describe("edge cases", () => {
            it("reverts when tokens and tokenAmounts lengths do not match", async () => {
                await expect(this.subject.transferAndPush(
                    this.deployer.address, this.deployer.address, [this.usdc.address], [BigNumber.from(1), BigNumber.from(1)], []
                )).to.be.reverted;
            });
            it("reverts when tokens are not sorted", async () => {
                await expect(this.subject.transferAndPush(
                    this.deployer.address, [this.weth.address, this.usdc.address], [BigNumber.from(1), BigNumber.from(1)], []
                )).to.be.revertedWith(Exceptions.INVARIANT)
            })
            it("reverts when tokens are not unique", async () => {
                await expect(
                    this.subject.transferAndPush(
                        this.deployer.address, [this.usdc.address, this.usdc.address], [BigNumber.from(1), BigNumber.from(1)], []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
            it("reverts when tokens not sorted nor unique", async () => {
                await expect(
                    this.subject.transferAndPush(
                        this.deployer.address, [this.weth.address, this.usdc.address, this.weth.address],
                        [BigNumber.from(1), BigNumber.from(1), BigNumber.from(1)],
                        []
                    )
                ).to.be.revertedWith(Exceptions.INVARIANT);
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {
                await withSigner(randomAddress(), async (signer) => {
                    await this.usdc.transfer(signer.address, BigNumber.from(1));
                    await this.usdc.connect(signer).approve(this.subject.address, BigNumber.from(1));

                    await expect(this.subject.connect(signer).transferAndPush(
                        signer.address, [this.usdc.address], [BigNumber.from(1)], []
                    )).to.not.be.reverted;
                });
            });
        });
    });
}