// TODO: replace "reverts with X" -> `reverts with ${Exceptions.X}`
describe("ERC20RootVaultGovernance", () => {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {});
        it("initializes MAX_PROTOCOL_FEE", async () => {});
        it("initializes MAX_MANAGEMENT_FEE", async () => {});
        it("initializes MAX_PERFORMANCE_FEE", async () => {});
    });

    describe("#delayedProtocolParams", () => {
        it("returns delayed protocol params", async () => {});

        describe("properties", () => {
            it("@property: does't not update by #stageDelayedProtocolParams", async () => {});
            it("@property: updates by #commitDelayedProtocolParams", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stagedDelayedProtocolParams", () => {
        it("returns staged delayed protocol params", async () => {});

        describe("properties", () => {
            it("@property: updates by #stageDelayedProtocolParams", async () => {});
            it("@property: resets by #commitDelayedProtocolParams", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#delayedProtocolPerVaultParams", () => {
        it("returns delayed protocol params per vault", async () => {});

        describe("properties", () => {
            it("@property: doesn't update by #stageDelayedProtocolPerVaultParams", async () => {});
            it("@property: updates by #commitDelayedProtocolPerVaultParams", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stagedDelayedProtocolPerVaultParams", () => {
        it("returns staged delayed protocol params per vault", async () => {});

        describe("properties", () => {
            it("@property: updates by #stageDelayedProtocolPerVaultParams", async () => {});
            it("@property: resets by #commitDelayedProtocolPerVaultParams", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stagedDelayedStrategyParams", () => {
        it("returns staged delayed strategy params", async () => {});

        describe("properties", () => {
            it("@property: updates by #stageDelayedStrategyParams", async () => {});
            it("@property: resets by #commitDelayedStrategyParams", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#delayedStrategyParams", () => {
        it("returns delayed strategy params", async () => {});

        describe("properties", () => {
            it("@property: doesn't update by #stageDelayedStrategyParams", async () => {});
            it("@property: updates by #commitDelayedStrategyParams", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#strategyParams", () => {
        it("returns strategy params", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stageDelayedStrategyParams", () => {
        it("stages delayed strategy params", async () => {});

        it("emits StageDelayedStrategyParams event", async () => {});

        describe("edge cases", () => {
            describe("when params.managementFee > MAX_MANAGEMENT_FEE", () => {
                it("reverts with LIMIT_OVERFLOW", async () => {});
            });

            describe("when params.performanceFee > MAX_PERFORMANCE_FEE", () => {
                it("reverts with LIMIT_OVERFLOW", async () => {});
            });

            describe("when initial delayed strategy params are empty", () => {
                it("allows to commit staged params instantly", async () => {});
            });

            describe("when passed unknown nft", () => {
                it("works", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: strategy", async () => {});
            it("allowed: admin", async () => {});
            it("denied: deployer", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#commitDelayedStrategyParams", () => {
        it("commits delayed strategy params", async () => {});

        it("emits CommitDelayedStrategyParams event", async () => {});

        describe("edge cases", () => {
            describe("when nothing has been staged yet", () => {
                it("reverts with NULL", async () => {});
            });

            describe("when governance delay has not passed yet", () => {
                it("reverts with TIMESTAMP", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: strategy", async () => {});
            it("allowed: admin", async () => {});
            it("denied: deployer", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#stageDelayedProtocolPerVaultParams", () => {
        it("stages delayed protocol params per vault", async () => {});

        it("emits StageDelayedProtocolPerVaultParams event", async () => {});

        describe("edge cases", () => {
            describe("when params.protocolFee > MAX_PROTOCOL_FEE", () => {
                it("reverts with LIMIT_OVERFLOW", async () => {});
            });

            describe("when initial delayed protocol params are empty", () => {
                it("allows to commit staged params instantly", async () => {});
            });

            describe("when passed unknown nft", () => {
                it("works", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: deployer", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#commitDelayedProtocolPerVaultParams", () => {
        it("commits delayed protocol params per vault", async () => {});

        it("emits CommitDelayedProtocolPerVaultParams event", async () => {});

        describe("edge cases", () => {
            describe("when nothing has been staged yet", () => {
                it("reverts with NULL", async () => {});
            });

            describe("when governance delay has not passed yet", () => {
                it("reverts with TIMESTAMP", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: deployer", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#setStrategyParams", () => {
        it("sets strategy params", async () => {});
        it("emits SetStrategyParams event", async () => {});

        describe("access control", () => {
            it("allowed: strategy", async () => {});
            it("allowed: admin", async () => {});
            it("denied: deployer", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#stageDelayedProtocolParams", () => {
        it("stages delayed protocol params", async () => {});
        it("emits StageDelayedProtocolParams event", async () => {});

        describe("edge cases", () => {
            describe("when initial delayed protocol params are empty", () => {
                it("allows to commit staged params instantly", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: deployer", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#commitDelayedProtocolParams", () => {
        it("commits delayed protocol params", async () => {});
        it("emits CommitDelayedProtocolParams event", async () => {});

        describe("edge cases", () => {
            describe("when nothing has been staged yet", () => {
                it("reverts with NULL", async () => {});
            });

            describe("when governance delay has not passed yet", () => {
                it("reverts with TIMESTAMP", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: deployer", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#createVault", () => {
        it("creates new ERC20RootVault", async () => {});
        it("initializes new ERC20RootVault with correct NFT", async () => {});
        it("emits VaultRegistered event", async () => {});

        describe("edge cases", () => {
            describe("when has zero subvaults", () => {
                // TODO: find out
            });
        });

        describe("access control", () => {
            it("allowed: has CREATE_VAULT permission", async () => {});
            it("denied: random address", async () => {});
        });
    });
});
