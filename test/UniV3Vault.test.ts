describe("UniV3Vault", () => {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {});

        it("initializes with correct NonfungiblePositionManager address", async () => {});

        it("initializes uniV3Nft with zero", async () => {

        });

        describe("edge cases", () => {
            describe("when uniswap v3 pool with given vaultTokens and fee not found", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#tvl", () => {
        it("returns initial tvl of (0, 0)", async () => {});

        describe("when pushed some tokens", () => {
            it("increases tvl", async () => {});
        });

        describe("when trades performed in the position range", () => {
            it("increases tokensOwed along with tvl", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#onERC721Received", () => {
        it("receives new uniswap v3 position", async () => {});

        it("transfers back previous nft", async () => {});

        describe("access control", () => {
            it("allowed operator: strategy", async () => {});

            it("allowed sender: NonfungiblePositionManager", async () => {});

            it("denied operator: random address", async function () {
                this.retries(4);
            });

            it("denied sender: random address", async function () {
                this.retries(4);
            });
        });

        describe("edge cases", () => {
            describe("when token0 of the received position not equals _vaultTokens[0]", () => {});

            describe("when token1 of the received position not equals _vaultTokens[1]", () => {});

            describe("when current position is not empty", () => {
                it("reverts", async () => {

                });
            });
        });
    });

    describe("#collectEarnings", () => {
        it("emits EarningsCollected event", async () => {});

        describe("access control", () => {
            it("allowed: strategy", async () => {});

            it("allowed: owner", async () => {});

            it("denied: random address", async function () {
                this.retries(4);
            });
        });

        describe("edge cases", () => {
            describe("when sender is approved and target destination is random address", () => {
                it("reverts", async () => {});
            });

            describe("when sender is approved and target destination is subvault", () => {
                it("passes", async () => {});
            });

            describe("when sender is owner and target destination is random address", () => {
                it("passes", async () => {});
            });

            describe("when sender is owner and target destination is subvault", () => {
                it("passes", async () => {});
            });
        });
    });

    describe("#push", () => {
        it("emits Pushed event", async () => {});

        describe("access control", () => {
            it("allowed: strategy", async () => {});

            it("allowed: owner", async () => {});

            it("denied: random address", async function () {
                this.retries(4);
            });
        });

        describe("edge cases", () => {
            describe("when not enough funds", () => {
                it("reverts", async () => {});
            });

            describe("when amount0Min exceeds allowance", () => {
                it("reverts", async () => {});
            });

            describe("when amount1Min exceeds allowance", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#transferAndPush", () => {

    });

    describe("#pull", () => {

    });
});
