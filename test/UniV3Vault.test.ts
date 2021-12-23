describe("UniV3Vault", () => {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {});

        it("initializes with correct NonfungiblePositionManager address", async () => {});

        describe("edge cases", () => {
            describe("when uniswap v3 pool with given vaultTokens and fee not found", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#tvl", () => {
        it("returns initial tvl (0, 0)", async () => {});

        describe("when added liquidity", () => {
            it("increases tvl", async () => {});
        });

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#onERC721Received", () => {
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
            describe("when received position's token0 != _vaultTokens[0]", () => {});

            describe("when received position's token1 != _vaultTokens[1]", () => {});
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

        describe("edge cases", () => {});
    });

    describe("#push", () => {});

    describe("#pull", () => {});
});
