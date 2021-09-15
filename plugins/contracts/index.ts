import { extendEnvironment } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { CONTRACTS } from "./constants";
import "./type-extensions";
import { ExternalContractName } from "./type-extensions";

extendEnvironment((hre: HardhatRuntimeEnvironment) => {
  hre.getExternalContract = async (name: ExternalContractName) => {
    const abi = require(`./abi/${name}.abi.json`);
    const address = (await hre.getNamedAccounts())[name];
    return await hre.ethers.getContractAt(abi, address);
  };
  hre.externalContracts = CONTRACTS;
});
