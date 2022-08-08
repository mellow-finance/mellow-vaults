import * as tdly from "@tenderly/hardhat-tenderly";
import { tenderly } from "hardhat";

async function main() {
    let address = "0x9CE6acAF30Af7D99DeEF179B99218B3EFAfe8C67";
  console.log("Manual Advanced: {MStrategy} deployed to:", address);

  tenderly.verify({
    address,
    name: "MStrategy",
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});