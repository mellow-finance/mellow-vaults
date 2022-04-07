import { BigNumber } from "ethers";
export default class Common {
    static readonly DENOMINATOR: BigNumber = BigNumber.from(10).pow(9);
    static readonly D18: BigNumber = BigNumber.from(10).pow(18);
    static readonly YEAR: BigNumber = BigNumber.from(365).mul(24).mul(3600);
    static readonly Q128: BigNumber = BigNumber.from(2).pow(128);
    static readonly Q96: BigNumber = BigNumber.from(2).pow(96);
    static readonly Q48: BigNumber = BigNumber.from(2).pow(48);
    static readonly Q160: BigNumber = BigNumber.from(2).pow(160);
    static readonly UNI_FEE_DENOMINATOR: BigNumber = BigNumber.from(10).pow(6);

}