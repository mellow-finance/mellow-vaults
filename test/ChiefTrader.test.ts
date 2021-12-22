describe("ChiefTrader", () => {
    before(async () => {});

    beforeEach(async () => {});

    describe("#constructor", () => {
        it("deployes a new `ChiefTrader` contract", async () => {});

        it("initializes `ProtocolGovernance` address", async () => {});

        describe("edge cases", () => {
            describe("when `protocolGovernance` argument is `0`", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#tradersCount", () => {
        it("returns the number of traders", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when a new trader is added", () => {
                it("`tradesCount` return value is increased by `1`", async () => {});
            });
        });
    });

    describe("#getTrader", () => {
        it("returns trader", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when trader doesn't exist", () => {
                it("returns zero address", async () => {});
            });
        });
    });

    describe("#traders", () => {
        it("returns a list of registered trader addresses", async () => {});

        describe("access control", () => {
            it("allowed: any address", async () => {});
        });

        describe("edge cases", () => {
            describe("when a new trader is added", () => {
                it("new trader is included at the end of the list", async () => {});
            });
        });
    });

    describe("#addTrader", () => {
        it("adds a new trader", async () => {});

        it("emits `AddedTrader` event", async () => {});

        describe("access control", () => {
            describe("denied: random address", () => {});
        });

        describe("edge cases", () => {
            describe("when interfaces don't match", () => {
                it("reverts", async () => {});
            });
        });
    });

    describe("#swapExactInput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {});
            });

            describe("when a path contains not allowed token", () => {});
        });
    });

    describe("#swapExactOutput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {});
            });

            describe("when a path contains not allowed token", () => {});
        });
    });

    describe("#supportsInterface", () => {
        describe("returns `true` on IChiefTrader", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `true` on ITrader", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `true` on ERC165", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `false` on `0x`", async () => {
            it("returns `false`", async () => {});
        });
    });
});
