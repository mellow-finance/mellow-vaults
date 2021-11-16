import { BigNumber } from "@ethersproject/bignumber";

export const CREATE_CELL_EVENT_HASH =
  "0xe423da5b0aa0eb7a8c8409551a7f9487952c6003da26568ea41ee22cf3133d4a";
export const VAULT_LIMITS = {
  'usdc': BigNumber.from(10).pow(18),
  'weth': BigNumber.from(10).pow(18),
};
export const TOKEN_LIMIT_PER_ADDRESS = BigNumber.from(10).pow(18);
