import { expect } from "chai";
import { ethers, deployments } from "hardhat";
import { encodeToBytes, randomAddress, sleep, withSigner, generateSingleParams } from "./library/Helpers";
import { contract } from "./library/setup";
import { ERC20Validator } from "./types";
import {
    PermissionIdsLibrary,
} from "../deploy/0000_utils";
import { ValidatorBehaviour } from "./behaviors/validator";
import Exceptions from "./library/Exceptions";
import { randomBytes, randomInt } from "crypto";
import { uint256 } from "./library/property";

type CustomContext = {
};

type DeployOptions = {};

contract<ERC20Validator, DeployOptions, CustomContext>("ERC20Validator", function () {

    const APPROVE_SELECTOR = "0x095ea7b3";

    before(async () => {
        this.deploymentFixture = deployments.createFixture(
            async (_, __?: DeployOptions) => {
                await deployments.fixture();
                const { address } = await deployments.get(
                    "ERC20Validator"
                );
                this.subject = await ethers.getContractAt(
                    "ERC20Validator",
                    address
                );
                return this.subject;
            }
        );
    });

    beforeEach(async () => {
        await this.deploymentFixture();
    }); 

    describe("#validate", () => {
        it("reverts if value != 0", async () => {
            await withSigner(randomAddress(), async (signer) => {
                await expect(
                    this.subject
                        .connect(signer)
                        .validate(
                            signer.address, 
                            randomAddress(),
                            generateSingleParams(uint256),
                            randomBytes(4),
                            randomBytes(randomInt(32))
                        )
                ).to.be.revertedWith(Exceptions.INVALID_VALUE);
            });
        });

        it("reverts if selector is not approve", async () => {
            await withSigner(randomAddress(), async (signer) => {
                await expect(
                    this.subject
                        .connect(signer)
                        .validate(
                            signer.address, 
                            randomAddress(),
                            0,
                            randomBytes(4),
                            randomBytes(randomInt(32))
                        )
                ).to.be.revertedWith(Exceptions.INVALID_SELECTOR);
            });
        });

        it("reverts if no transfer permission", async () => {
            await withSigner(randomAddress(), async (signer) => {
                await expect(
                    this.subject
                        .connect(signer)
                        .validate(
                            signer.address, 
                            randomAddress(),
                            0,
                            APPROVE_SELECTOR,
                            randomBytes(randomInt(32))
                        )
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
        });

        it("reverts if no approve permission", async () => {
            await withSigner(randomAddress(), async (signer) => {
                let tokenAddress = randomAddress();
                this.protocolGovernance.connect(this.admin).stagePermissionGrants(tokenAddress, [PermissionIdsLibrary.ERC20_TRANSFER])
                await sleep(await this.protocolGovernance.governanceDelay())
                this.protocolGovernance.connect(this.admin).commitPermissionGrants(tokenAddress)
                await expect(
                    this.subject
                        .connect(signer)
                        .validate(
                            signer.address, 
                            tokenAddress,
                            0,
                            APPROVE_SELECTOR,
                            randomBytes(32)
                        )
                ).to.be.revertedWith(Exceptions.FORBIDDEN);
            });
        });

        it("return, because spender can approve", async () => {
            await withSigner(randomAddress(), async (signer) => {
                let tokenAddress = randomAddress();
                let spenderAddress = randomAddress();
                this.protocolGovernance.connect(this.admin).stagePermissionGrants(tokenAddress, [PermissionIdsLibrary.ERC20_TRANSFER])
                this.protocolGovernance.connect(this.admin).stagePermissionGrants(spenderAddress, [PermissionIdsLibrary.ERC20_APPROVE])
                await sleep(await this.protocolGovernance.governanceDelay())
                this.protocolGovernance.connect(this.admin).commitAllPermissionGrantsSurpassedDelay()
                await expect(
                    this.subject
                        .connect(signer)
                        .validate(
                            signer.address, 
                            tokenAddress,
                            0,
                            APPROVE_SELECTOR,
                            encodeToBytes(["address"], [spenderAddress])
                        )
                ).to.not.be.reverted;
            });
        });

        it("return, because sender is trusted strategy", async () => {
            await withSigner(randomAddress(), async (signer) => {
                let tokenAddress = randomAddress();
                let spenderAddress = randomAddress();
                this.protocolGovernance.connect(this.admin).stagePermissionGrants(tokenAddress, [PermissionIdsLibrary.ERC20_TRANSFER])
                this.protocolGovernance.connect(this.admin).stagePermissionGrants(spenderAddress, [PermissionIdsLibrary.ERC20_APPROVE_RESTRICTED])
                this.protocolGovernance.connect(this.admin).stagePermissionGrants(signer.address, [PermissionIdsLibrary.ERC20_TRUSTED_STRATEGY])
                await sleep(await this.protocolGovernance.governanceDelay())
                this.protocolGovernance.connect(this.admin).commitAllPermissionGrantsSurpassedDelay()
                await expect(
                    this.subject
                        .connect(signer)
                        .validate(
                            signer.address, 
                            tokenAddress,
                            0,
                            APPROVE_SELECTOR,
                            encodeToBytes(["address"], [spenderAddress])
                        )
                ).to.not.be.reverted;
            });
        });
    });

    ValidatorBehaviour.call(this, {});
});
