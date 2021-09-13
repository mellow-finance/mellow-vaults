import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function ({deployments, getNamedAccounts}: HardhatRuntimeEnvironment) {
  const {deploy} = deployments;

  const {deployer, uniswapV3PositionManager} = await getNamedAccounts();

  await deploy('UniV3Cells', {
    from: deployer,
    args: [uniswapV3PositionManager, "Mellow UniV3 Cells V1", "MUCV1"],
    log: true,
  });
};
export default func;
func.tags = ['UniV3Cells'];