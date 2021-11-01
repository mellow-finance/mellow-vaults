import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  // const {deployments, getNamedAccounts} = hre;
  // const {deploy} = deployments;

  // const {deployer} = await getNamedAccounts();

  // const deployResult = await deploy('ERC20VaultFactory', {
  //   from: deployer,
  //   args: [],
  //   log: true,
  //   autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  // });
};
export default func;
func.tags = ['ERC20VaultFactory'];

