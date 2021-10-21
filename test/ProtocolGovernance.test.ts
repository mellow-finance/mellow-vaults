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
import Exceptions from "./library/Exceptions";
import { BigNumber } from "@ethersproject/bignumber";
import { setTimestamp } from "./library/Helpers";


type GovernanceParams = [
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
    let user1: Signer;
    let user2: Signer;
    let timestamp: number;
    let timeout: number;
    let timeShift: number;
    let params: GovernanceParams;
    let paramsZero: GovernanceParams;
    let paramsTimeout: GovernanceParams;
    let paramsEmpty: GovernanceParams;
    let paramsDefault: GovernanceParams;
    let defaultGovernanceDelay: number;

    before(async () => {
        ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance");
        [deployer, stranger, user1, user2] = await ethers.getSigners();
        timeout = 10**4;
        defaultGovernanceDelay = 1;
        timeShift = 10**10;
        params = [
            BigNumber.from(1), 
            BigNumber.from(defaultGovernanceDelay), 
            BigNumber.from(3), 
            BigNumber.from(4), 
            BigNumber.from(5), 
            await user1.getAddress(), 
            await user2.getAddress()
        ];
    });

    beforeEach(async () => {

        protocolGovernance = await ProtocolGovernance.deploy(
            deployer.getAddress(),
            params
        );

        await network.provider.send("evm_increaseTime", [defaultGovernanceDelay]);
        await network.provider.send('evm_mine');
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
            it("has default max tokens per vault", async () => {
                expect(
                    await protocolGovernance.maxTokensPerVault()
                ).to.be.equal(params[0]);
            });

            it("has default governance delay", async () => {
                expect(
                    await protocolGovernance.governanceDelay()
                ).to.be.equal(params[1]);
            });

            it("has default strategy performance fee", async () => {
                expect(
                    await protocolGovernance.strategyPerformanceFee()
                ).to.be.equal(params[2]);
            });

            it("has default protocol performance fee", async () => {
                expect(
                    await protocolGovernance.protocolPerformanceFee()
                ).to.be.equal(params[3]);
            });

            it("has default protocol exit fee", async () => {
                expect(
                    await protocolGovernance.protocolExitFee()
                ).to.be.equal(params[4]);
            });

            it("has default protocol treasury", async () => {
                expect(
                    await protocolGovernance.protocolTreasury()
                ).to.be.equal(params[5]);
            });

            it("has default gateway vault manager", async () => {
                expect(
                    await protocolGovernance.gatewayVaultManager()
                ).to.be.equal(params[6]);
            });
        });
    });

    describe("setPendingParams", () => {
        it("sets the params", () => {
            describe("when called once", () => {
                it("sets the params", async () => {
                    await protocolGovernance.setPendingParams(params);
                    expect(
                        await protocolGovernance.pendingParams()
                    ).to.deep.equal(params);
                });
            });

            describe("when called twice", () => {
                it("sets the params", async () => {
                    const paramsNew = [
                        BigNumber.from(6), 
                        BigNumber.from(7), 
                        BigNumber.from(8), 
                        BigNumber.from(9), 
                        BigNumber.from(10), 
                        await user1.getAddress(), 
                        await user2.getAddress()
                    ];
                    await protocolGovernance.setPendingParams(params);
                    await protocolGovernance.setPendingParams(paramsNew);
        
                    expect(
                        await protocolGovernance.pendingParams()
                    ).to.deep.equal(paramsNew);
                });
            });
        });

        it("sets governance delay", async () => {
            timestamp = setTimestamp() + timeShift;

            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(params);
            expect(Math.abs(await protocolGovernance.pendingParamsTimestamp() - timestamp)).to.be.lessThanOrEqual(10);
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(stranger).setPendingParams(params)
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitParams", () => {
        describe("when callen by not admin", () => {
            it("reverts", async () => {
                paramsZero = [
                    BigNumber.from(1), 
                    BigNumber.from(0), 
                    BigNumber.from(2), 
                    BigNumber.from(3), 
                    BigNumber.from(4), 
                    await user1.getAddress(), 
                    await user2.getAddress()
                ];
                await protocolGovernance.setPendingParams(paramsZero);
    
                await expect(
                    protocolGovernance.connect(stranger).commitParams()
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });

        describe("when governance delay has not passed", () => {
            describe("when call immediately", () => {
                it("reverts", async () => {
                    paramsZero = [
                        BigNumber.from(1), 
                        BigNumber.from(0), 
                        BigNumber.from(2), 
                        BigNumber.from(3), 
                        BigNumber.from(4), 
                        await user1.getAddress(), 
                        await user2.getAddress()
                    ];
                    paramsTimeout = [
                        BigNumber.from(1), 
                        BigNumber.from(timeout), 
                        BigNumber.from(2), 
                        BigNumber.from(3), 
                        BigNumber.from(4), 
                        await user1.getAddress(), 
                        await user2.getAddress()
                    ];
                    await protocolGovernance.setPendingParams(paramsTimeout);

                    await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                    await network.provider.send('evm_mine');

                    await protocolGovernance.commitParams();
        
                    await protocolGovernance.setPendingParams(paramsZero);
                    await expect(
                        protocolGovernance.commitParams()
                    ).to.be.revertedWith(Exceptions.TIMESTAMP);
                });
            });
            
            describe("when delay has almost passed", () => {
                it("reverts", async () => {
                    paramsZero = [
                        BigNumber.from(1), 
                        BigNumber.from(0), 
                        BigNumber.from(2), 
                        BigNumber.from(3), 
                        BigNumber.from(4), 
                        await user1.getAddress(), 
                        await user2.getAddress()
                    ];
                    paramsTimeout = [
                        BigNumber.from(1), 
                        BigNumber.from(timeout), 
                        BigNumber.from(2), 
                        BigNumber.from(3), 
                        BigNumber.from(4), 
                        await user1.getAddress(), 
                        await user2.getAddress()
                    ];
                    await protocolGovernance.setPendingParams(paramsTimeout);

                    await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                    await network.provider.send('evm_mine');

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
                paramsEmpty = [
                    BigNumber.from(0), 
                    BigNumber.from(0), 
                    BigNumber.from(2), 
                    BigNumber.from(3), 
                    BigNumber.from(4), 
                    await user1.getAddress(), 
                    await user2.getAddress()
                ];

                await protocolGovernance.setPendingParams(paramsEmpty);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await expect(
                    protocolGovernance.commitParams()
                ).to.be.revertedWith(Exceptions.EMPTY_PARAMS);
            });
        });

        it("commits params", async () => {
            paramsZero = [
                BigNumber.from(1), 
                BigNumber.from(0), 
                BigNumber.from(2), 
                BigNumber.from(3), 
                BigNumber.from(4), 
                await user1.getAddress(), 
                await user2.getAddress()
            ];
            await protocolGovernance.setPendingParams(paramsZero);

            await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
            await network.provider.send('evm_mine');

            await protocolGovernance.commitParams();
            expect(await protocolGovernance.params()).to.deep.equal(paramsZero);
        });

        it("deletes pending params", async () => {
            paramsZero = [
                BigNumber.from(1), 
                BigNumber.from(0), 
                BigNumber.from(2), 
                BigNumber.from(3), 
                BigNumber.from(4), 
                await user1.getAddress(), 
                await user2.getAddress()
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
            await protocolGovernance.setPendingParams(paramsZero);

            await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
            await network.provider.send('evm_mine');

            await protocolGovernance.commitParams();
            expect(await protocolGovernance.pendingParams()).to.deep.equal(paramsDefault);
        });

        it("deletes pending params timestamp", async () => {
            paramsTimeout = [
                BigNumber.from(1), 
                BigNumber.from(timeout), 
                BigNumber.from(2), 
                BigNumber.from(3), 
                BigNumber.from(4), 
                await user1.getAddress(), 
                await user2.getAddress()
            ];

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
        it("sets pending list", async () => {
            await protocolGovernance.setPendingClaimAllowlistAdd([
                user1.getAddress(), 
                user2.getAddress()
            ]);

            expect(
                await protocolGovernance.pendingClaimAllowlistAdd()
            ).to.deep.equal([
                await user1.getAddress(), 
                await user2.getAddress()
            ]);
        });

        it("sets correct pending timestamp with zero gonernance delay", async () => {
            paramsZero = [
                BigNumber.from(1), 
                BigNumber.from(0), 
                BigNumber.from(2), 
                BigNumber.from(3), 
                BigNumber.from(4), 
                await user1.getAddress(), 
                await user2.getAddress()
            ];

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(paramsZero);

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([
                user1.getAddress(), 
                user2.getAddress()
            ]);

            expect(
                Math.abs(await protocolGovernance.pendingClaimAllowlistAddTimestamp() - timestamp)
            ).to.be.lessThanOrEqual(10);
        });

        it("sets correct pending timestamp with non-zero governance delay", async () => {
            paramsTimeout = [
                BigNumber.from(1), 
                BigNumber.from(timeout), 
                BigNumber.from(2), 
                BigNumber.from(3), 
                BigNumber.from(4), 
                await user1.getAddress(), 
                await user2.getAddress()
            ];

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');

            await protocolGovernance.setPendingParams(paramsTimeout);

            timestamp += 10**6;
            await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
            await network.provider.send('evm_mine');
            await protocolGovernance.commitParams();

            await protocolGovernance.setPendingClaimAllowlistAdd([
                user1.getAddress(), 
                user2.getAddress()
            ]);

            expect(
                Math.abs(await protocolGovernance.pendingClaimAllowlistAddTimestamp() - (timestamp + timeout))
            ).to.be.lessThanOrEqual(10);
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(stranger).setPendingClaimAllowlistAdd([])
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });

    describe("commitClaimAllowlistAdd", () => {
        describe("appends zero address to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();
                expect(
                    await protocolGovernance.claimAllowlist()
                ).to.deep.equal([]);
            });
    
        });
        
        describe("appends one address to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(),
                ]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();
                expect(
                    await protocolGovernance.claimAllowlist()
                ).to.deep.equal([
                    await user1.getAddress(),
                ]);
            });
    
        });
        
        describe("appends multiple addresses to list", () => {
            it("appends", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),
                ]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();

                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(), 
                    user2.getAddress()
                ]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();

                expect(
                    await protocolGovernance.claimAllowlist()
                ).to.deep.equal([
                    await deployer.getAddress(),
                    await user1.getAddress(), 
                    await user2.getAddress()
                ]);
            });
        });

        describe("when callen by not admin", () => {
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
                paramsTimeout = [
                    BigNumber.from(1), 
                    BigNumber.from(timeout), 
                    BigNumber.from(2), 
                    BigNumber.from(3), 
                    BigNumber.from(4), 
                    await user1.getAddress(), 
                    await user2.getAddress()
                ];

                timestamp += 10**6;
                await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
                await network.provider.send('evm_mine');
                await protocolGovernance.setPendingParams(paramsTimeout);
    
                timestamp += 10**6;
                await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
                await network.provider.send('evm_mine');
                await protocolGovernance.commitParams();
                
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(), 
                    user2.getAddress()
                ]);

                await expect(
                    protocolGovernance.commitClaimAllowlistAdd()
                ).to.be.revertedWith(Exceptions.TIMESTAMP);
            });
        });
    });

    describe("removeFromClaimAllowlist", async () => {
        describe("when removing non-existing address", () => {
            it("does nothing", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    user1.getAddress(), 
                    user2.getAddress()
                ]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(stranger.getAddress());
                expect(await protocolGovernance.claimAllowlist()).to.deep.equal([
                    await user1.getAddress(), 
                    await user2.getAddress()
                ]);
            });
        });
        describe("when remove called once", () => {
            it("removes the address", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),  
                    user1.getAddress(), 
                    user2.getAddress()
                ]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(user1.getAddress());
                expect([
                    await protocolGovernance.isAllowedToClaim(await deployer.getAddress()) &&
                    await protocolGovernance.isAllowedToClaim(await user2.getAddress()), 
                    await protocolGovernance.isAllowedToClaim(await user1.getAddress()) 
                ]).to.deep.equal([true, false]);
            });
    
        });

        describe("when remove called twice", () => {
            it("removes the addresses", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),  
                    user1.getAddress(), 
                    user2.getAddress()
                ]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(user1.getAddress());
                await protocolGovernance.removeFromClaimAllowlist(user2.getAddress());
                expect([
                    await protocolGovernance.isAllowedToClaim(await deployer.getAddress()),
                    await protocolGovernance.isAllowedToClaim(await user1.getAddress()) &&
                    await protocolGovernance.isAllowedToClaim(await user2.getAddress()) 
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when remove called twice on the same address", () => {
            it("removes the address and does not fail then", async () => {
                await protocolGovernance.setPendingClaimAllowlistAdd([
                    deployer.getAddress(),
                    user1.getAddress(), 
                    user2.getAddress()
                ]);

                await network.provider.send("evm_increaseTime", [(params[1]).toNumber()]);
                await network.provider.send('evm_mine');

                await protocolGovernance.commitClaimAllowlistAdd();
                await protocolGovernance.removeFromClaimAllowlist(user2.getAddress());
                await protocolGovernance.removeFromClaimAllowlist(user2.getAddress());
                expect([
                    await protocolGovernance.isAllowedToClaim(await deployer.getAddress()) && 
                    await protocolGovernance.isAllowedToClaim(await user1.getAddress()),
                    await protocolGovernance.isAllowedToClaim(await user2.getAddress()) 
                ]).to.deep.equal([true, false]);
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                await expect(
                    protocolGovernance.connect(stranger).removeFromClaimAllowlist(deployer.getAddress())
                ).to.be.revertedWith(Exceptions.ADMIN);
            });
        });
    });
});
