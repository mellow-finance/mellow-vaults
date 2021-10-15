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
import { getNamedAccounts } from "hardhat";
import { time } from "console";


type Params = [
    maxTokensPerVault: BigNumber, 
    governanceDelay: BigNumber, 
    strategyPerformanceFee: BigNumber, 
    protocolPerformanceFee: BigNumber, 
    protocolExitFee: BigNumber, 
    protocolTreasury: String, 
    gatewayVaultManager: String
];

describe("ProtocolGovernance", () => {
    let ProtocolGovernance: ContractFactory;
    let protocolGovernance: Contract;
    let deployer: Signer;
    let stranger: Signer;
    let stranger1: Signer;
    let stranger2: Signer;
    let timestamp: number;
    let timeout: number;
    let params: Params;
    let paramsZero: Params;
    let paramsTimeout: Params;
    let paramsEmpty: Params;
    let paramsDefault: Params;

    before(async () => {
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        [deployer, stranger, stranger1, stranger2] = await ethers.getSigners();
        timeout = 10**4;
        params = [
            BigNumber.from(1), 
            BigNumber.from(2), 
            BigNumber.from(3), 
            BigNumber.from(4), 
            BigNumber.from(5), 
            await stranger1.getAddress(), 
            await stranger2.getAddress()
        ];
        paramsZero = [
            BigNumber.from(1), 
            BigNumber.from(0), 
            BigNumber.from(2), 
            BigNumber.from(3), 
            BigNumber.from(4), 
            await stranger1.getAddress(), 
            await stranger2.getAddress()
        ];
        paramsTimeout = [
            BigNumber.from(1), 
            BigNumber.from(timeout), 
            BigNumber.from(2), 
            BigNumber.from(3), 
            BigNumber.from(4), 
            await stranger1.getAddress(), 
            await stranger2.getAddress()
        ];
        paramsEmpty = [
            BigNumber.from(0), 
            BigNumber.from(0), 
            BigNumber.from(2), 
            BigNumber.from(3), 
            BigNumber.from(4), 
            await stranger1.getAddress(), 
            await stranger2.getAddress()
        ];
        paramsDefault = [
            BigNumber.from(0), 
            BigNumber.from(0), 
            BigNumber.from(0), 
            BigNumber.from(0), 
            BigNumber.from(0), 
            ethers.constants.AddressZero, 
            ethers.constants.AddressZero
        ];
    });

    beforeEach(async () => {
        protocolGovernance = await ProtocolGovernance.deploy(deployer.getAddress());
    });

    describe("constructor", () => {
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

    describe("setPendingParams", () => {
        describe("sets params", () => {
            it("when called once", async () => {
                await protocolGovernance.setPendingParams(params);
                expect(
                    await protocolGovernance.pendingParams()
                ).to.deep.equal(params);
            });

            it("when called twice", async () => {
                const paramsNew = [
                    BigNumber.from(6), 
                    BigNumber.from(7), 
                    BigNumber.from(8), 
                    BigNumber.from(9), 
                    BigNumber.from(10), 
                    await stranger1.getAddress(), 
                    await stranger2.getAddress()
                ];
                await protocolGovernance.setPendingParams(params);
                await protocolGovernance.setPendingParams(paramsNew);
    
                expect(
                    await protocolGovernance.pendingParams()
                ).to.deep.equal(paramsNew);
            });
        });

        it("sets governance delay", async () => {
            timestamp = Math.ceil(new Date().getTime() / 1000) + 10**6;

            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(params);
            expect(Math.abs(await protocolGovernance.pendingParamsTimestamp() - timestamp)).to.be.lessThanOrEqual(10);
        });

        describe("when not called by admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(stranger).setPendingParams(params)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitParams", () => {
        describe("when not called by admin", () => {
            it("reverts", async () => {
                await protocolGovernance.setPendingParams(paramsZero);
    
                await expect(
                    protocolGovernance.connect(stranger).commitParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when governance delay has not passed", () => {
            describe("when call immediately", () => {
                it("reverts", async () => {
                    await protocolGovernance.setPendingParams(paramsTimeout);
                    await protocolGovernance.commitParams();
        
                    await protocolGovernance.setPendingParams(paramsZero);
                    await expect(
                        protocolGovernance.commitParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
            
            describe("when delay has almost passed", () => {
                it("reverts", async () => {
                    await protocolGovernance.setPendingParams(paramsTimeout);
                    await protocolGovernance.commitParams();

                    await network.provider.send("evm_increaseTime", [timeout - 2]);
                    await network.provider.send("evm_mine");
        
                    await protocolGovernance.setPendingParams(paramsZero);
                    await expect(
                        protocolGovernance.commitParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
        });

        describe("when governanceDelay is 0 and maxTokensPerVault is 0", () => {
            it("reverts", async () => {
                await protocolGovernance.setPendingParams(paramsEmpty);
                await expect(
                    protocolGovernance.commitParams()
                ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
            });
        });

        it("commits params", async () => {
            await protocolGovernance.setPendingParams(paramsZero);
            await protocolGovernance.commitParams();
            expect(await protocolGovernance.params()).to.deep.equal(paramsZero);
        });

        it("deletes pending params", async () => {
            await protocolGovernance.setPendingParams(paramsZero);
            await protocolGovernance.commitParams();
            expect(await protocolGovernance.pendingParams()).to.deep.equal(paramsDefault);
        });

        it("deletes pending params timestamp", async () => {
            timestamp += 10**6;

            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(paramsTimeout);

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            expect(
                await protocolGovernance.pendingParamsTimestamp()
            ).to.be.equal(BigNumber.from(0));
        });
    });

    
    describe("setPendingClaimAllowlistAdd", () => {
        describe("when not called by admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(stranger).setPendingClaimAllowlistAdd([])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        it("sets pending list", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([
                stranger1.getAddress(), 
                stranger2.getAddress()
            ]);

            expect(
                await protocolGovernance.pendingClaimAllowlistAdd()
            ).to.deep.equal([
                await stranger1.getAddress(), 
                await stranger2.getAddress()
            ]);
        });

        it("sets correct pending timestamp with zero gonernance delay", async () => {
            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(paramsZero);

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([
                stranger1.getAddress(), 
                stranger2.getAddress()
            ]);

            expect(
                Math.abs(await protocolGovernance.pendingClaimAllowlistAddTimestamp() - timestamp)
            ).to.be.lessThanOrEqual(10);
        });

        it("sets correct pending timestamp with non-zero governance delay", async () => {
            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(paramsTimeout);

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([
                stranger1.getAddress(), 
                stranger2.getAddress()
            ]);

            expect(
                Math.abs(await protocolGovernance.pendingClaimAllowlistAddTimestamp() - (timestamp + timeout))
            ).to.be.lessThanOrEqual(10);
        });
    });

    describe("commitClaimAllowlistAdd", () => {
        describe("when not called by admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(stranger).commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when does not have pre-set claim allow list add timestamp", () => {
            it("reverts", async () => {
                timestamp += 10**6;
                await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
                await network.provider.send('evm_mine');
    
                await expect(
                    protocolGovernance.commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
        
        describe("when governance delay has not passed", () => {
            it("reverts", async () => {
                timestamp += 10**6;
                await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
                await network.provider.send('evm_mine');
                await protocolGovernance.setPendingParams(paramsTimeout);
    
                timestamp += 10**6;
                await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
                await network.provider.send('evm_mine');
                await protocolGovernance.commitParams();
                
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    stranger1.getAddress(), 
                    stranger2.getAddress()
                ]);

                await expect(
                    protocolGovernance.commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
        
        describe("appends one address to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    stranger1.getAddress(), 
                    stranger2.getAddress()
                ]);

                await protocolGovernance.commitClaimAllowlistAdd();
                expect(
                    await protocolGovernance.claimAllowlist()
                ).to.deep.equal([
                    await stranger1.getAddress(), 
                    await stranger2.getAddress()
                ]);
            });
    
        });
        
        describe("aappends multiple addresses to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),
                    stranger.getAddress()
                ]);
                await protocolGovernance.commitClaimAllowlistAdd();

                await protocolGovernance.setPendingClaimAllowlistAdd([
                    stranger1.getAddress(), 
                    stranger2.getAddress()
                ]);
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
    });

    describe("removeFromClaimAllowlist", async () => {
        describe("when not called by admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(stranger).removeFromClaimAllowlist(deployer.getAddress())
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when removing unexisting address", () => {
            it("passes", async () => {
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
        });
        describe("when remove called once", () => {
            it("removes", async () => {
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
    
        });

        describe("when remove called twice", () => {
            it("removes", async () => {
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
});
