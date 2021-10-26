import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {deployer} = await getNamedAccounts();

  await deploy('VaultGovernanceFactory', {
    from: deployer,
    args: [],
    log: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  });
};
export default func;
func.tags = ['SimpleERC20'];

let hre: HardhatRuntimeEnvironment = {
  config: undefined,
  hardhatArguments: undefined,
  tasks: undefined,
  run: function (name: string, taskArguments?: any): Promise<any> {
    throw new Error('Function not implemented.');
  },
  network: undefined,
  artifacts: undefined,
  deployments: undefined,
  getNamedAccounts: function (): Promise<{ [name: string]: string; }> {
    throw new Error('Function not implemented.');
  },
  getUnnamedAccounts: function (): Promise<string[]> {
    throw new Error('Function not implemented.');
  },
  getChainId: function (): Promise<string> {
    throw new Error('Function not implemented.');
  },
  companionNetworks: {}
};