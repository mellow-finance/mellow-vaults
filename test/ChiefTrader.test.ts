describe("ChiefTrader", () => {
    before(async () => {});

    beforeEach(async () => {});

    describe("#constructor", () => {

    });

    describe("#tradersCount", () => {
        it("returns traders count", async () => {});

        describe("when added new trader", () => {
            it("returns updated traders count", async () => {

            });
        });
    });

    describe("#getTrader", () => {
        it("returns trader", async () => {});

        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("returns zero address", async () => {

                });
            });
        });
    });

    describe("#traders", () => {
        it("returns registered traders", async () => {});

        describe("when added a new trader", () => {
            it("returns updated registered traders", async () => {

            });
        })
    });

    describe("#addTrader", () => {
        it("adds new trader", async () => {});

        it("emits `AddedTrader` event", async () => {});

        describe("access control", () => {
            describe("denied: random address", () => {

            });
        });

        describe("edge cases", () => {
            describe("when interfaces don't match", () => {
                it("reverts", async () => {

                });
            });
        });
    });

    describe("#swapExactInput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {

                });
            });

            describe("when a path contains not allowed token", () => {

            });
        });
    });

    describe("#swapExactOutput", () => {
        describe("edge cases", () => {
            describe("when passed unknown trader id", () => {
                it("reverts", async () => {

                });
            });

            describe("when a path contains not allowed token", () => {

            });
        });
    });

    describe("#supportsInterface", () => {
        describe("returns `true` on chief trader interface", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `true` on trader interface", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `true` on ERC165", async () => {
            it("returns `true`", async () => {});
        });

        it("returns `false` on zero", async () => {
            it("returns `false`", async () => {});
        });
    });
});
