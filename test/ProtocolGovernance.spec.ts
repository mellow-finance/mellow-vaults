import Exceptions from "./library/Exceptions";

describe("ProtocolGovernance", () => {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {});
    });

    describe("#hasPermission", () => {
        it("checks if an address has a permission", async () => {});
        describe("properties", () => {
            it("@property: returns false on a random address", async () => {});
            it("@property: isn't affected by a staged permission", async () => {});
            it("@property: affected by a committed permission", async () => {});
            it("@property: when forceAllowMask is set, returns true for any address", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when permission is unknown", () => {
                it("returns false", async () => {});
            });
        });
    });

    describe("#hasAllPermissions", () => {
        it("checks if an address has all specified permissions", async () => {});

        describe("properties", () => {
            it("@property: returns false on a random address", async () => {});
            it("@property: is not affected by staged permissions", async () => {});
            it("@property: is affected by committed permissions", async () => {});
            it("@property: when forceAllowMask is set, returns true for any address", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("on unknown permission id", () => {
                it("returns false", async () => {});
            });
        });
    });

    describe("#permissionAddresses", () => {
        it("returns addresses that has any permission set to true", async () => {});

        describe("properties", () => {
            it("@property: address is returned <=> permission mask is not 0", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#permissionAddressCount", () => {
        it("returns number of addresses that has any permission set to true", async () => {});

        describe("properties", () => {
            it("@property: always equals to the length of #permissionAddresses result", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#permissionAddressAt", () => {
        it("returns address at the given index", async () => {});

        describe("properties", () => {
            it("@property: always equals to the element at the same position in the #permissionAddresses result", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    // rename the method and all other to be consistent, i.e. hasStagedGrantPermission
    describe("#hasStagedPermission", () => {
        it("checks if a given address has a specific grant permission staged", async () => {});

        describe("properties", () => {
            it("@property: returns false on a random address", async () => {});
            it("@property: updated when permission is staged", async () => {});
            it("@property: reset on commit", async () => {});
            it("@property: updated on new stage", async () => {});
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
        it("returns timestamp after which permissions can be commited for a given address", async () => {});

        describe("properties", () => {
            it("@property: timestamp resets on restage", async () => {});
            it("@property: for a random address it is 0", async () => {});
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
