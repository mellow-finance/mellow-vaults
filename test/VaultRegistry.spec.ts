describe("VaultRegistry", () => {
    describe("#constructor", () => {
        it("creates VaultRegistry", async () => {
            
        });
    });

    describe("#vaults", () => {
        it("returns correct vaults", async () => {
            
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
        });
    });

    describe("#vaultForNft", () => {
        it("returns correct ERC20Vault for existing nftERC20", async () => {
           
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
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

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
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

        describe("access control:", () => {
            it("allowed: VaultGovernance", async () => {
                
            });
        });

        describe("edge cases", () => {
            describe("when address parameter is not an address of vault", () => {
                it("does not fail", async () => {

                });
            });

            describe("when vault or owner adresses == 0x0", () => {
                it("does not fail", async () => {

                });
            });
        });
    });

    describe("#protocolGovernance", () => {
        it("has correct protocolGovernance", async () => {
            
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
        });
    });

    describe("#stagedProtocolGovernance", () => {
        it("returns correct stagedProtocolGovernance", async () => {
            
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
                it("returns address zero", async () => {
                    
                });
            });
        });
    });

    describe("#stagedProtocolGovernanceTimestamp", () => {
        it("returns correct timestamp", async () => {
                    
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
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

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
        });
    });

    describe("#stageProtocolGovernance", () => {
        it("stages new protocol governance", () => {

        });

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {
                
            });
        });

        describe("edge cases", () => {
            describe("when new ProtocolGovernance is a zero address", () => {
                it("does not fail", async () => {

                });
            });
        });
    });

    describe("#commitStagedProtocolGovernance", () => {
        it("commits staged ProtocolGovernance", async () => {
            
        });

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {
                
            });
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
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

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {
                
            });
        });
    });

    describe("#isLocked", () => {
        it("checks if token is locked", async () => {
            
        });

        describe("access control:", () => {
            it("allowed: any address", async () => {
                
            });
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

        describe("access control:", () => {
            it("allowed: nft owner", async () => {
                
            });
        });

        describe("edge cases", () => {
            describe("when nft has already been locked", () => {
                it("does not fail", async () => {
                    
                });
            });
        });
    });
});
