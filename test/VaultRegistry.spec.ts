describe("VaultRegistry", () => {
    describe("#constructor", () => {
        it("creates VaultRegistry", async () => {
            
        });
    });

    describe("#vaults", () => {
        it("returns correct vaults", async () => {
            
        });
    });

    describe("#vaultForNft", () => {
        it("returns correct ERC20Vault for existing nftERC20", async () => {
           
        });

        describe("edge cases", () => {
            describe("when ERC20Vault does not exist", () => {
                it("returns zero nftERC20", async () => {
                    
                });
            });
        })
    });

    describe("#nftForVault", () => {
        it("returns correct ERC20Vault for nftERC20", async () => {
           
        });

        describe("edge cases", () => {
            describe("when nftERC20 does not exist", () => {
                it("returns zero address", async () => {
                    
                });
            });
        });
    });

    describe("#registerVault", () => {
        it("registers existing ERC20Vault", async () => {
            
        });

        describe("when called not by VaultGovernance", async () => {
            it("reverts", async () => {
                
            });
        });
    });

    describe("#protocolGovernance", () => {
        it("has correct protocolGovernance", async () => {
            
        });
    });

    describe("#stagedProtocolGovernance", () => {
        it("returns correct stagedProtocolGovernance", async () => {
            
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
                it("returns address zero", async () => {
                    
                });
            });
        });
    });

    describe("stagedProtocolGovernanceTimestamp", () => {
        it("returns correct timestamp", async () => {
                    
        });

        describe("edge cases", () => {
            describe("when nothing is staged", () => {
                it("returns 0", async () => {
            
                });
            });
        });
    });

    describe("#vaultsCount", () => {
        it("returns correct vaults count", async () => {
            
        });
    });

    describe("#stageProtocolGovernance", () => {
        it("stages new protocol governance", () => {

        });

        describe("edge cases", () => {
            describe("when called not by protocol governance admin", () => {
                it("reverts", async () => {
                    
                });
            });
        });
    });

    describe("#commitStagedProtocolGovernance", () => {
        it("commits staged ProtocolGovernance", async () => {
            
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
                it("reverts", async () => {
                    
                });
            });

            describe("when called by stranger", () => {
                it("reverts", async () => {
                    
                });
            });

            describe("when called too early", () => {
                it("reverts", async () => {
                    
                });
            });
        });
    });

    describe("#adminApprove", () => {
        it("approves token to new address", async () => {
            
        });

        describe("edge cases", () => {
            describe("when called not by admin", () => {
                it("reverts", async () => {
                    
                });
            });
        });
    });

    describe("#isLocked", () => {
        it("checks if token is locked", async () => {
            
        });

        describe("edge cases", () => {
            describe("when token is invalid", () => {
                it("returns false", async () => {

                });
            });
        });
    });

    describe("lockNft", () => {
        it("locks nft for any transfer", async () => {

        });

        describe("edge cases", () => {
            describe("when called not by nft owner", () => {
                it("reverts", async () => {
                    
                });
            });
        });
    });
});
