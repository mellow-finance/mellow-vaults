import { BigNumber } from "@ethersproject/bignumber";
import { pit, uint256 } from "./library/property";

pit("works", {}, uint256, uint256, async (x: BigNumber, y: BigNumber) => {
    return x.lte(y);
});
