describe("VaultRegistry", () => {
    describe("#constructor", () => {
        it("creates VaultRegistry", async () => {});
        it("initializes ProtocolGovernance address", async () => {});
        it("initializes ERC721 token name", async () => {});
        it("initializes ERC721 token symbol", async () => {});
    });

    describe("#vaults", () => {
        it("returns all registered vaults", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#vaultForNft", () => {
        it("resolves Vault address by VaultRegistry NFT", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when Vault is not registered in VaultRegistry", () => {
                it("returns zero", async () => {});
            });
        });
    });

    describe("#nftForVault", () => {
        it("resolves VaultRegistry NFT by Vault address", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when VaultRegistry NFT is not registered in VaultRegistry", () => {
                it("returns zero address", async () => {});
            });
        });
    });

    describe("#isLocked", () => {
        it("checks if token is locked (not transferable)", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when VaultRegistry NFT is not registered in VaultRegistry", () => {
                it("returns false", async () => {});
            });
        });
    });

    describe("#protocolGovernance", () => {
        it("returns ProtocolGovernance address", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#stagedProtocolGovernance", () => {
        it("returns ProtocolGovernance address staged for commit", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
                it("returns zero address", async () => {});
            });

            describe("right after #commitStagedProtocolGovernance was called", () => {
                it("returns zero address", async () => {});
            });
        });
    });

    describe("#stagedProtocolGovernanceTimestamp", () => {
        it("returns timestamp after which #commitStagedProtocolGovernance can be called", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when nothing is staged", () => {
                it("returns 0", async () => {});
            });
            describe("right after #commitStagedProtocolGovernance was called", () => {
                it("returns 0", async () => {});
            });
        });
    });

    describe("#vaultsCount", () => {
        it("returns the number of registered vaults", async () => {});

        describe("access control:", () => {
            it("allowed: any address", async () => {});
        });
        describe("edge cases", () => {
            describe("when new vault is registered", () => {
                it("is increased by 1", async () => {});
            });
        });
    });

    describe("#registerVault", () => {
        it("mints an ERC721 NFT", async () => {});
        it("binds minted NFT to Vault address", async () => {});
        it("transfers minted NFT to owner specified in args", async () => {});
        it("emits VaultRegistered event", async () => {});

        describe("properties", () => {
            it("@property: minted NFT equals to vaultRegistry#vaultsCount", async () => {});
        });

        describe("access control:", () => {
            it("allowed: any VaultGovernance registered in ProtocolGovernance", async () => {});
            it("denied: any other address", async () => {});
        });

        describe("edge cases", () => {
            describe("when address doesn't conform to IVault interface (IERC165)", () => {
                it("reverts", async () => {});
            });

            describe("when owner adresses is zero", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#stageProtocolGovernance", () => {
        it("stages new ProtocolGovernance for commit", () => {});
        it("sets the stagedProtocolGovernanceTimestamp after which #commitStagedProtocolGovernance can be called", async () => {});

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {});
            it("denied: any other address", async () => {});
        });

        describe("edge cases", () => {
            describe("when new ProtocolGovernance is a zero address", () => {
                it("does not fail", async () => {});
            });
        });
    });

    describe("#commitStagedProtocolGovernance", () => {
        it("commits staged ProtocolGovernance", async () => {});
        it("resets staged ProtocolGovernance", async () => {});
        it("resets ProtocolGovernanceTimestamp", async () => {});

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {});
            it("denied: any other address", async () => {});
        });

        describe("edge cases", () => {
            describe("when nothing staged", () => {
                it("reverts", async () => {});
            });

            describe("when called before stagedProtocolGovernanceTimestamp", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#adminApprove", () => {
        it("approves token to new address", async () => {});

        describe("access control:", () => {
            it("allowed: ProtocolGovernance Admin", async () => {});
            it("denied: any other address", async () => {});
        });
        describe("edge cases", () => {
            describe("when NFT doesn't exist", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("lockNft", () => {
        it("locks NFT (disables any transfer)", async () => {});
        it("emits TokenLocked event", async () => {});

        describe("access control:", () => {
            it("allowed: NFT owner", async () => {});
            it("allowed: any other address", async () => {});
        });

        describe("edge cases", () => {
            describe("when NFT has already been locked", () => {
                it("succeeds", async () => {});
            });
        });
    });
});
