import { expect } from "chai";
import { 
    ethers,
    network
} from "hardhat";
import { 
    ContractFactory, 
    Contract, 
    Signer 
} from "ethers";
import Exceptions from "./utils/Exceptions";
import { BigNumber } from "@ethersproject/bignumber";

describe("ProtocolGovernance", () => {
    let ProtocolGovernance: ContractFactory;
    let protocolGovernance: Contract;
    let deployer: Signer;
    let stranger: Signer;
    let stranger1: Signer;
    let stranger2: Signer;
    let timestamp: number;
    let timeout: number;

    beforeEach(async () => {
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        [deployer, stranger, stranger1, stranger2] = await ethers.getSigners();
        protocolGovernance = await ProtocolGovernance.deploy(deployer.getAddress());
        timeout = 10**4;
    });

    describe("create new protocol", () => {
        it("has empty pending claim allow list", async () => {
            expect(
                await protocolGovernance.claimAllowlist()
            ).to.be.empty;
        });
        
        it("has empty pending claim allow list add", async () => {
            expect(
                await protocolGovernance.pendingClaimAllowlistAdd()
            ).to.be.empty;
        });

        it("does not allow deployer to claim", async () => {
            expect(
                await protocolGovernance.isAllowedToClaim(deployer.getAddress())
            ).to.be.equal(false);
        });

        it("does not allow stranger to claim", async () => {
            expect(
                await protocolGovernance.isAllowedToClaim(stranger.getAddress())
            ).to.be.equal(false);
        });

        describe("initial params struct values", () => {
            it("has 0 max tokens per vault", async () => {
                expect(
                    await protocolGovernance.maxTokensPerVault()
                ).to.be.equal(0);
            });

            it("has no governance delay", async () => {
                expect(
                    await protocolGovernance.governanceDelay()
                ).to.be.equal(0);
            });

            it("has no strategy performance fee", async () => {
                expect(
                    await protocolGovernance.strategyPerformanceFee()
                ).to.be.equal(0);
            });

            it("has no protocol performance fee", async () => {
                expect(
                    await protocolGovernance.protocolPerformanceFee()
                ).to.be.equal(0);
            });

            it("has no protocol exit fee", async () => {
                expect(
                    await protocolGovernance.protocolExitFee()
                ).to.be.equal(0);
            });

            it("has 0x0 protocol treasury", async () => {
                expect(
                    await protocolGovernance.protocolTreasury()
                ).to.be.equal(ethers.constants.AddressZero);
            });

            it("has 0x0 gateway vault manager", async () => {
                expect(
                    await protocolGovernance.gatewayVaultManager()
                ).to.be.equal(ethers.constants.AddressZero);
            });
        });
    });

    describe("set pending params", () => {
        it("checks admin premissions", async () => {
            await expect(
                protocolGovernance.connect(stranger).setPendingParams(
                    [1, 0, 1, 1, 1, ethers.constants.AddressZero, ethers.constants.AddressZero])
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("sets pending params", async () => {
            await protocolGovernance.setPendingParams(
                [1, 2, 3, 4, 5, ethers.constants.AddressZero, ethers.constants.AddressZero]
            );

            expect(
                await protocolGovernance.pendingParams()
            ).to.deep.equal([
                BigNumber.from(1), 
                BigNumber.from(2), 
                BigNumber.from(3), 
                BigNumber.from(4), 
                BigNumber.from(5), 
                ethers.constants.AddressZero, 
                ethers.constants.AddressZero
            ]);
        });

        it("sets pending params governance delay", async () => {
            timestamp = Math.ceil(new Date().getTime() / 1000) + 10**6;

            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(
                [1, timeout, 1, 1, 1, ethers.constants.AddressZero, ethers.constants.AddressZero]
            );

            expect(Math.abs(await protocolGovernance.pendingParamsTimestamp() - timestamp)).to.be.lessThanOrEqual(10);
        });        
    });

    describe("commit pending params", () => {
        it("checks admin premissions", async () => {
            await protocolGovernance.setPendingParams(
                [1, 0, 1, 1, 1, ethers.constants.AddressZero, ethers.constants.AddressZero]
            );

            await expect(
                protocolGovernance.connect(stranger).commitParams()
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("waits governance delay", async () => {
            timestamp += 10**6;

            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(
                [1, timeout, 1, 1, 1, ethers.constants.AddressZero, ethers.constants.AddressZero]
            );
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingParams(
                [1, 0, 1, 1, 1, ethers.constants.AddressZero, ethers.constants.AddressZero]
            );
            await expect(
                protocolGovernance.commitParams()
            ).to.be.revertedWith(Exceptions.TIMESTAMP);
        });

        it("has not empty params", async () => {
            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.setPendingParams(
                [0, 0, 1, 1, 1, ethers.constants.AddressZero, ethers.constants.AddressZero]
            );
            await expect(
                protocolGovernance.commitParams()
            ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
        });

        it("commits params", async () => {
            await protocolGovernance.setPendingParams(
                [1, 0, 3, 4, 5, await stranger1.getAddress(), await stranger2.getAddress()]
            );
            await protocolGovernance.commitParams();
            expect(await protocolGovernance.params()).to.deep.equal([
                BigNumber.from(1), 
                BigNumber.from(0), 
                BigNumber.from(3), 
                BigNumber.from(4), 
                BigNumber.from(5), 
                await stranger1.getAddress(), 
                await stranger2.getAddress()
            ]);
        });

        it("deletes pending params", async () => {
            await protocolGovernance.setPendingParams(
                [1, 0, 3, 4, 5, await stranger1.getAddress(), await stranger2.getAddress()]
            );
            await protocolGovernance.commitParams();
            expect(await protocolGovernance.pendingParams()).to.deep.equal([
                BigNumber.from(0), 
                BigNumber.from(0), 
                BigNumber.from(0), 
                BigNumber.from(0), 
                BigNumber.from(0), 
                ethers.constants.AddressZero, 
                ethers.constants.AddressZero
            ]);
        });

        it("deletes pending params timestamp", async () => {
            timestamp += 10**6;

            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(
                [1, timeout, 3, 4, 5, await stranger1.getAddress(), await stranger2.getAddress()]
            );

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            expect(
                await protocolGovernance.pendingParamsTimestamp()
            ).to.be.equal(BigNumber.from(0));
        });
    });

    
    describe("set pending claim allow list add ", () => {
        it("checks admin premissions", async () => {
            await expect(
                protocolGovernance.connect(stranger).setPendingClaimAllowlistAdd([])
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("sets pending list", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([stranger1.getAddress(), stranger2.getAddress()]);
            expect(
                await protocolGovernance.pendingClaimAllowlistAdd()
            ).to.deep.equal([await stranger1.getAddress(), await stranger2.getAddress()]);
        });

        it("sets correct pending timestamp with zero gonernance delay", async () => {
            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(
                [1, 0, 0, 0, 0, await stranger1.getAddress(), await stranger2.getAddress()]
            );

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([stranger1.getAddress(), stranger2.getAddress()]);
            expect(
                Math.abs(await protocolGovernance.pendingClaimAllowlistAddTimestamp() - timestamp)
            ).to.be.lessThanOrEqual(10);
        });

        it("sets correct pending timestamp with non-zero governance delay", async () => {
            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(
                [0, timeout, 0, 0, 0, await stranger1.getAddress(), await stranger2.getAddress()]
            );

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([stranger1.getAddress(), stranger2.getAddress()]);
            expect(
                Math.abs(await protocolGovernance.pendingClaimAllowlistAddTimestamp() - (timestamp + timeout))
            ).to.be.lessThanOrEqual(10);
        });
    });

    describe("commit claim allow list add", () => { 
        it("checks admin premissions", async () => {
            await expect(
                protocolGovernance.connect(stranger).commitClaimAllowlistAdd()
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("has pre-set claim allow list add timestamp", async () => {
            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await expect(
                protocolGovernance.commitClaimAllowlistAdd()
            ).to.be.revertedWith(Exceptions.TIMESTAMP);
        });

        it("waits governance delay", async () => {
            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.setPendingParams(
                [1, timeout, 0, 0, 0, await stranger1.getAddress(), await stranger2.getAddress()]
            );

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();
            
            await protocolGovernance.setPendingClaimAllowlistAdd([stranger1.getAddress(), stranger2.getAddress()]);
            await expect(
                protocolGovernance.commitClaimAllowlistAdd()
            ).to.be.revertedWith(Exceptions.TIMESTAMP);
        });

        it("adds addresses to claim allow list", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([stranger1.getAddress(), stranger2.getAddress()]);
            await protocolGovernance.commitClaimAllowlistAdd();
            expect(
                await protocolGovernance.claimAllowlist()
            ).to.deep.equal([await stranger1.getAddress(), await stranger2.getAddress()]);
        });

        it("appends addresses to claim allow list", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([deployer.getAddress(), stranger.getAddress()]);
            await protocolGovernance.commitClaimAllowlistAdd();
            await protocolGovernance.setPendingClaimAllowlistAdd([stranger1.getAddress(), stranger2.getAddress()]);
            await protocolGovernance.commitClaimAllowlistAdd();
            expect(
                await protocolGovernance.claimAllowlist()
            ).to.deep.equal([
                await deployer.getAddress(), 
                await stranger.getAddress(), 
                await stranger1.getAddress(), 
                await stranger2.getAddress()
            ]);
        });
    });

    describe("remove from claim allow list", async () => {
        it("checks admin premissions", async () => {
            await expect(
                protocolGovernance.connect(stranger).removeFromClaimAllowlist(deployer.getAddress())
            ).to.be.revertedWith(Exceptions.ADMIN);
        });

        it("passes removing unexisting address", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([
                stranger1.getAddress(), 
                stranger2.getAddress()
            ]);
            await protocolGovernance.commitClaimAllowlistAdd();
            await protocolGovernance.removeFromClaimAllowlist(stranger.getAddress());
            expect(await protocolGovernance.claimAllowlist()).to.deep.equal([
                await stranger1.getAddress(), 
                await stranger2.getAddress()
            ]);
        });

        it("removes existing address once", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([
                deployer.getAddress(), 
                stranger.getAddress(), 
                stranger1.getAddress(), 
                stranger2.getAddress()
            ]);
            await protocolGovernance.commitClaimAllowlistAdd();
            await protocolGovernance.removeFromClaimAllowlist(stranger.getAddress());
            expect([
                await protocolGovernance.isAllowedToClaim(await deployer.getAddress()) && 
                await protocolGovernance.isAllowedToClaim(await stranger1.getAddress()) &&
                await protocolGovernance.isAllowedToClaim(await stranger2.getAddress()), 
                await protocolGovernance.isAllowedToClaim(await stranger.getAddress()) 
            ]).to.deep.equal([true, false]);
        });

        it("removes existing addresses", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([
                deployer.getAddress(), 
                stranger.getAddress(), 
                stranger1.getAddress(), 
                stranger2.getAddress()
            ]);
            await protocolGovernance.commitClaimAllowlistAdd();
            await protocolGovernance.removeFromClaimAllowlist(stranger.getAddress());
            await protocolGovernance.removeFromClaimAllowlist(stranger2.getAddress());
            expect([
                await protocolGovernance.isAllowedToClaim(await deployer.getAddress()) && 
                await protocolGovernance.isAllowedToClaim(await stranger1.getAddress()),
                await protocolGovernance.isAllowedToClaim(await stranger.getAddress()) &&
                await protocolGovernance.isAllowedToClaim(await stranger2.getAddress()) 
            ]).to.deep.equal([true, false]);
        });
    });
});
