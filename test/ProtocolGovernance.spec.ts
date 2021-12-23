describe("ProtocolGovernance", () => {
    
    describe("#constructor", () => {
        it("deploys a new contract", async () => {

        })
        
        describe("initial params struct values", () => {
            it("has initial params struct", async () => {
               
            });

            it("by default permissionless == true", async () => {

            });

            it("has max tokens per vault", async () => {

            });

            it("has governance delay", async () => {
               
            });
        });
    });

    describe("#setPendingParams", () => {
        it("sets pending params", async () => {
                
        });

        describe("when called twice", () => {
            it("sets pending params", async () => {
                
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
               
            });
        });
    });

    describe("#commitParams", () => {
        it("commits params and deletes pending params and pending params timestamp", async () => {
            
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
               
            });
        });

        describe("when governance delay has not passed", () => {
            describe("when call immediately", () => {
                it("reverts", async () => {
                    
                });
            });

            describe("when delay has almost passed", () => {
                it("reverts", async () => {
                    
                });
            });
        });

        describe("when governanceDelay is 0 and maxTokensPerVault is 0", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when commited twice", () => {
            it("reverts", async () => {
                
            });
        });
    });

    describe("#setPendingClaimAllowlistAdd", () => {
        it("sets pending claim allow list and pending timestamp", async () => {
        
        });

        describe("when governance delay == 0", () => {
            it("sets pending list and pending timestamp", async () => {
            
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                
            });
        });
    });

    describe("#setPendingVaultGovernancesAdd", () => {
        it("sets pending vault governances and pendingVaultGovernancesAddTimestamp", async () => {
                
        });

        describe("when there are repeating addresses", () => {
            it("sets sets pending vault governances and pendingVaultGovernancesAddTimestamp", async () => {
                
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                
            });
        });
    });

    describe("#commitVaultGovernancesAdd", () => {
        it("commits vault governance add", async () => {
            
        });

        describe("when there are repeating addresses", () => {
            it("commits vault governance add", async () => {
                
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not passed or has almost passed", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when pendingVaultGovernancesAddTimestamp has not been set", () => {
            it("reverts", async () => {
                
            });
        });
    });

    describe("#commitClaimAllowlistAdd", () => {
        describe("appends zero address to list", () => {
            it("appends", async () => {
                
            });
        });

        describe("appends one address to list", () => {
            it("appends", async () => {
               
            });
        });

        describe("appends multiple addresses to list", () => {
            it("appends", async () => {
                
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when does not have pre-set claim allow list add timestamp", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when governance delay has not passed", () => {
            it("reverts", async () => {
                
            });
        });
    });

    describe("#removeFromClaimAllowlist", async () => {
        it("removes the address", async () => {
               
        });

        describe("when removing non-existing address", () => {
            it("does nothing", async () => {
                
            });
        });

        describe("when remove called twice", () => {
            it("removes the addresses", async () => {
                
            });
        });

        describe("when remove called twice on the same address", () => {
            it("removes the address and does not fail then", async () => {
                
            });
        });

        describe("when callen by not admin", () => {
            it("reverts", async () => {
                
            });
        });
    });

    describe("#removeFromVaultGovernances", () => {
        describe("when called by not admin", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when address is not in vault governances", () => {
            it("does not fail", async () => {
                
            });
        });

        describe("when address is a vault governance", () => {
            describe("when attempt to remove one address", () => {
                it("removes", async () => {
                    
                });
            });
            describe("when attempt to remove multiple addresses", () => {
                it("removes", async () => {
                    
                });
            });
        });
    });

    describe("#setPendingTokenWhitelistAdd", () => {
        it("does not allow stranger to set pending token whitelist", async () => {
            
        });

        it("sets pending token whitelist add and timestamp", async () => {
            
        });
    });

    describe("#commitTokenWhitelistAdd", () => {
        it("commits pending token whitelist", async () => {
            
        });

        describe("when called noy by admin", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when setPendingTokenWhitelistAdd has not been called", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when governance delay has not passed or has almost passed", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when setting to identic addresses", () => {
            it("passes", async () => {
                
            });
        });
    });

    describe("#removeFromTokenWhitelist", () => {
        describe("when called not by admin", () => {
            it("reverts", async () => {
                
            });
        });

        describe("when passed an address which is not in token whitelist", () => {
            it("passes", async () => {
                
            });
        });

        it("removes", async () => {
            
        });

        describe("when call commit on removed token", () => {
            it("passes", async () => {
                
            });
        });
    });
});
