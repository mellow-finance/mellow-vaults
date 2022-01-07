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
        it("checks if given address has speceific permission set to true", async () => {});

        describe("properties", () => {
            it("@property: returns false on a random address", async () => {});
            it("@property: is not affected by staged permissions", async () => {});
            it("@property: is affected by committed permissions", async () => {});
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

    describe("#hasAllPermissions", () => {
        it("checks if given address has a subset of permissions set to true", async () => {});

        describe("properties", () => {
            it("@property: returns false on a random address", async () => {});
            it("@property: is not affected by staged permissions", async () => {});
            it("@property: is affected by committed permissions", async () => {});
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

    describe("#permissionAddresses", () => {
        it("returns addresses that has any permission set to true", async () => {});

        describe("properties", () => {
            it("@property: address removes when all existing permissions are revoked", async () => {});
            it("@property: address is added when new staged permissions are comitted", async () => {});
            it("@property: unaffected if added address that has no permissions", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#permissionAddressCount", () => {
        it("returns number of addresses that has any permission set to true", async () => {});

        describe("properties", () => {
            it("@property: number of addresses is affected by staged permissions", async () => {});
            it("@property: number of addresses is affected by committed permissions", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#permissionAddressAt", () => {
        it("returns address at the given index", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#hasStagedPermission", () => {
        it("checks if the given address has speceific permission staged to be granted", async () => {});

        describe("properties", () => {
            it("@property: returns false on a random address", async () => {});
            it("@property: is affected by staged permissions", async () => {});
            it("@property: resets on commit", async () => {});
            it("@property: resets when restaged", async () => {});
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

    describe("#grantedPermissionAddressTimestamps", () => {
        it("returns commit timestamp for given address", async () => {});

        describe("properties", () => {
            it("@property: timestamp resets on restage", async () => {});
        });

        describe("edge cases", () => {
            describe("when given unknown address", () => {
                it("returns zero", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#params", () => {
        it("returns governance params", async () => {});

        describe("properties", () => {
            it("@property: not affected by newly set params", async () => {});
            it("@property: affected by committed params", async () => {});
        });
        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#pendingParams", () => {
        it("returns pending params", async () => {});

        describe("edge cases", () => {
            describe("when no pending params", () => {
                it("returns zero params", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#pendingParamsTimestamp", () => {
        it("returns pending params commit timestamp", async () => {});

        describe("edge cases", () => {
            describe("when no pending params", () => {
                it("returns zero timestamp", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#rawPermissionMask", () => {
        it("returns raw permission mask for the given address", async () => {});

        describe("properties", () => {
            it("@property: is not affected by staged permissions", async () => {});
            it("@property: is affected by committed permissions", async () => {});
        });

        describe("edge cases", () => {
            describe("on unknown address", () => {
                it("returns zero", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#permissionMask", () => {
        it("returns permission mask for the given address that includes forceAllowMask", async () => {});

        describe("properties", () => {
            it("@property: is not affected by staged permissions", async () => {});
            it("@property: is affected by committed permissions", async () => {});
            it("@property: is affected by forceAllowMask", async () => {});
        });

        describe("edge cases", () => {
            describe("when given unknown address", () => {
                it("returns zero", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#addressesByPermissionIdRaw", () => {
        it("returns addresses that has the given raw permission set to true", async () => {});

        describe("properties", () => {
            it("@property: updates when the given permission is revoked", async () => {});
            it("@property: unaffected by forceAllowMask", async () => {});
        });

        describe("edge cases", () => {
            describe("on unknown permission id", () => {
                it("returns empty array", async () => {});
            });
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stagedPermissionAddresses", () => {
        it("returns addresses that has any permission staged to be granted", async () => {});

        describe("properties", () => {
            it("@property: updates when granted permission for a new address", async () => {});
            it("@property: clears when staged permissions committed", async () => {});
            it("@property: unaffected when permissions revoked instantly", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stagedGrantedPermissionMasks", () => {
        it("returns raw permission masks for addresses that has any permission staged to be granted", async () => {});

        describe("properties", () => {
            it("@property: updates when granted permission for a new address", async () => {});
            it("@property: clears when staged permissions committed", async () => {});
            it("@property: unaffected when permissions revoked instantly", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#permissionless", () => {
        it("returns initial value of true", async () => {});

        describe("properties", () => {
            it("@property: updates when pending params are committed", async () => {});
            it("@property: doesn't update when new pending params are set", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#maxTokensPerVault", () => {
        it("returns initial value of true", async () => {});

        describe("properties", () => {
            it("@property: updates when pending params are committed", async () => {});
            it("@property: doesn't update when new pending params are set", async () => {});
            it("@property: could not be set to zero", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#governanceDelay", () => {
        it("returns initial value of zero", async () => {});

        describe("properties", () => {
            it("@property: updates when pending params are committed", async () => {});
            it("@property: doesn't update when new pending params are set", async () => {});
            it("@property: could not exceed MAX_GOVERNANCE_DELAY", async () => {});
            it("@property: could not be set to zero", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#protocolTreasury", () => {
        it("returns initial value of true", async () => {});

        describe("properties", () => {
            it("@property: updates when pending params are committed", async () => {});
            it("@property: doesn't update when new pending params are set", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#forceAllowMask", () => {
        it("returns initial value of zero", async () => {});

        describe("properties", () => {
            it("@property: updates when pending params are committed", async () => {});
            it("@property: doesn't update when new pending params are set", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#setPendingParams", () => {
        it("sets new pending params", async () => {});
        it("emits PendingParamsSet event", async () => {});

        describe("edge cases", () => {
            describe("when given invalid params", () => {
                describe("when maxTokensPerVault is zero", () => {
                    it("reverts with ${NULL}", async () => {});
                });

                describe("when governanceDelay is zero", () => {
                    it("reverts with ${NULL}", async () => {});
                });

                describe("when governanceDelay exceeds MAX_GOVERNANCE_DELAY", () => {
                    it("reverts with ${LIMIT_OVERFLOW}", async () => {});
                });
            });
        });

        describe("access control", () => {
            it("allowed: admin", async () => {});
            it("denied: random address", async () => {});
        });
    });
});
