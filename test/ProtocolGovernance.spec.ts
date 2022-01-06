describe("ProtocolGovernance", () => {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {});

        describe("edge cases", () => {
            describe("when admin is zero address", () => {
                it("reverts with ADDRESS_ZERO", async () => {});
            });
        });
    });

    describe("#hasPermission", () => {
        it("returns false on a random address", async () => {});

        describe("when staged grant permission for address", () => {
            it("returns false on the given address", async () => {});

            describe("when committed staged permissions", () => {
                it("returns true on the given address", async () => {});
            });
        });

        describe("edge cases", () => {
            describe("on unknown permission id", () => {
                it("returns false", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#hasStagedPermission", () => {
        it("returns false on a random address", async () => {});

        describe("when staged grant permission for address", () => {
            it("returns false on the given address", async () => {});

            describe("when committed staged permissions", () => {
                it("returns true on the given address", async () => {});
            });
        });

        describe("edge cases", () => {
            describe("on unknown permission id", () => {
                it("returns false", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stagedToCommitAt", () => {
        it("returns initial vaule of zero", async () => {});

        describe("when staged grant permissions", () => {
            it("returns current timestamp + governance delay", async () => {});

            describe("when committed staged addresses", () => {
                it("resets to zero", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#params", () => {
        it("returns initial governance params", async () => {});

        describe("when new governance params are set", () => {
            it("returns initial governance params", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#pendingParams", () => {
        it("returns initial pending params", async () => {});

        describe("when new pending params were set", () => {
            it("returns new pending params", async () => {});
        });

        describe("when new params were committed", () => {
            it("resets pending params", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#pendingParamsTimestamp", () => {
        it("returns initial timestamp of zero", async () => {});

        describe("when new pending params were set", () => {
            it("returns current timestamp + governance delay", async () => {});

            describe("when new params were committed", () => {
                it("resets timestamp to zero", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#permissionless", () => {
        it("returns initial value of true", async () => {});

        describe("when new params were set but not yet committed", () => {
            it("doesn't change", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#maxTokensPerVault", () => {
        it("returns initial value of zero", async () => {});

        describe("when new params were set but not yet committed", () => {
            it("doesn't change", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#governanceDelay", () => {
        it("returns initial value of zero", async () => {});

        describe("when new params were set but not yet committed", () => {
            it("doesn't change", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#protocolTreasury", () => {
        it("returns initial value of address zero", async () => {});

        describe("when new params were set but not yet committed", () => {
            it("doesn't change", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stageGrantPermissions", () => {
        it("stages permissions to be granted for the given address", async () => {});

        describe("edge cases", () => {
            // TODO: add edge cases
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#commitStagedPermissions", () => {
        it("commits staged permissions", async () => {});

        it("sets stagedToCommitAt() to zero", async () => {});

        it("emits CommittedStagedPermissions", async () => {});

        describe("edge cases", () => {
            describe("when nothing is staged", () => {
                it("reverts with INVARIANT", async () => {});
            });

            describe("when governance delay not passed yet", () => {
                it("reverts with TIMESTAMP", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#revokePermissionsInstant", () => {
        it("revokes permissions from the given address", async () => {});

        describe("edge cases", () => {
            describe("when given address didn't have one of the given permissions initially", () => {
                it("reverts with INVALID_TARGET", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#rollbackStagedPermissions", () => {
        it("rolls back staged permission", async () => {});

        it("sets stagedToCommitAt() to zero", async () => {});

        it("emits RolledBackStagedPermissions", async () => {});

        describe("edge cases", () => {
            describe("when nothing is staged", () => {
                it("passes", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: random address", async () => {});
        });
    });

    describe("#setPendingParams", () => {
        it("sets pending governance params", async () => {});

        it("emits PendingParamsSet event", async () => {});

        describe("edge cases", () => {
            describe("governance params validation", () => {
                describe("when new governance delay is higher than MAX_GOVERNANCE_DELAY", () => {
                    it("reverts", async () => {});
                });

                describe("when new governance delay is zero", () => {
                    it("reverts", async () => {});
                });

                describe("when new max tokens per vault is zero", () => {
                    it("reverts", async () => {});
                });
            });

            describe("multiple calls", () => {});
        });

        describe("access control", () => {
            it("allowed: protocol governance admin", async () => {});

            it("denied: deployer", async () => {});

            it("denied: random address", async () => {});
        });
    });

    describe("#commitParams", () => {
        it("commits new governance params", async () => {});

        it("emits ParamsCommitted event", async () => {});

        describe("edge cases", () => {
            describe("when params not set", () => {
                it("reverts", async () => {});
            });

            describe("when governance delay not passed yet", () => {
                it("reverts", async () => {});
            });

            describe("when committed twice in a row", () => {
                it("reverts on the second time", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: protocol governance admin", async () => {});

            it("denied: deployer", async () => {});

            it("denied: random address", async () => {});
        });
    });
});
