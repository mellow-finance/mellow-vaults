describe("UniV2Trader", () => {
    describe("#constructor", () => {
        it("deploys a new contract", async () => {});

        it("initializes with correct UniswapV2Router02 address", async () => {});

        describe("edge cases", () => {
            describe("when `_router` is zero address", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#swapExactInput", () => {
        it("swaps exact amount of `token0` for `token1`", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when amount is 0", () => {
                it("reverts", async () => {});
            });

            describe("when token0 is address zero", () => {
                it("reverts", async () => {});
            });

            describe("when token1 is address zero", () => {
                it("reverts", async () => {});
            });

            describe("when pool (token0, token1) doesn't exist on uniswap v2", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#swapExactOutput", () => {
        it("swaps token0 for the exact amount of token1", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when amount is 0", () => {
                it("reverts", async () => {});
            });

            describe("when token0 is address zero", () => {
                it("reverts", async () => {});
            });

            describe("when token1 is address zero", () => {
                it("reverts", async () => {});
            });

            describe("when pool (token0, token1) doesn't exist on uniswap v2", () => {
                it("reverts", async () => {});
            });

            describe("when leftovers happen", () => {
                it("returns them to the recipient", async () => {});
            });
        });
    });

    describe("#supportsInterface", () => {
        it("returns true on ITrader", async () => {});

        it("returns true on ERC165", async () => {});

        it("returns false on 0xffffffff", async () => {});

        it("returns false on random interfaceId", async () => {});
    });
});
