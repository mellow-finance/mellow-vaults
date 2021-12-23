describe("UniV3Trader", () => {
    describe("#constructor", () => {});

    describe("#swapRouter", () => {
        it("returns correct swapRouter address", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });
    });

    describe("#swapExactInput", () => {
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

            describe("when pool (token0, token1, fee) doesn't exist on uniswap v3", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#swapExactOutput", () => {
        describe("edge cases", () => {
            describe("when leftovers happen", () => {
                it("returns them", async () => {});
            });

            describe("when amount is 0", () => {
                it("reverts", async () => {});
            });

            describe("when token0 is address zero", () => {
                it("reverts", async () => {});
            });

            describe("when token1 is address zero", () => {
                it("reverts", async () => {});
            });

            describe("when pool (token0, token1, fee) doesn't exist on uniswap v3", () => {
                it("reverts", async () => {});
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
