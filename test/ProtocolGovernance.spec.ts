describe("ProtocolGovernance", () => {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {

        });
        
        it("sets correct initial admin", async () => {

        });

        describe("edge cases", () => {
            describe("when admin is zero address", () => {
                it("reverts", async () => {

                });
            });
        });
    });

    describe("#hasPermission", () => {
        it("returns true when permission is set", async () => {

        });

        it("returns false when permission is not set", async () => {

        });

        describe("edge cases", () => {
            describe("on unknown permission id", () => {
                it("returns false", async () => {

                });
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {

            });
        });
    });

    describe("#hasStagedPermission", () => {
        it("returns true when permission is staged", async () => {

        });

        it("returns false when permission is not staged", async () => {

        });

        describe("edge cases", () => {
            describe("on unknown permission id", () => {
                it("returns false", async () => {

                });
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {

            });
        })
    });

    describe("#stagedToCommitAt", () => {
        describe("access control", () => {
            it("allowed: any address", async () => {

            });
        });
    });

    describe("#permissionless", () => {

    });

    describe("#maxTokensPerVault", () => {

    });

    describe("#governanceDelay", () => {

    });

    describe("#protocolTreasury", () => {

    });

    describe("#stageGrantPermissions", () => {

    });

    describe("#commitStagedPermissions", () => {

    });

    describe("#revokePermissionsInstant", () => {

    });

    describe("#setPendingParams", () => {
        it("sets pending governance params", async () => {

        });

        it("emits PendingParamsSet event", async () => {

        });

        describe("edge cases", () => {

        });

        describe("access control", () => {
            it("allowed: protocol governance admin", async () => {

            });

            it("denied: deployer", async () => {});

            it("denied: random address", async () => {});
        });
    });

    describe("#commitParams", () => {
        it("commits new governance params", async () => {

        });

        it("emits ParamsCommitted event", async () => {

        });

        describe("edge cases", () => {
            describe("when params not set", () => {
                it("reverts", async () => {});
            });

            describe("when governance delay not passed yet", () => {
                it("reverts", async () => {

                });
            });
            
        });

        describe("access control", () => {
            it("allowed: protocol governance admin", async () => {

            });

            it("denied: deployer", async () => {});

            it("denied: random address", async () => {});
        });
    });
});
