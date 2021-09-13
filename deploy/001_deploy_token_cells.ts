import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function ({deployments, getNamedAccounts}: HardhatRuntimeEnvironment) {
  const {deploy} = deployments;

  const {deployer, simpleERC20Beneficiary} = await getNamedAccounts();

  await deploy('TokenCells', {
    from: deployer,
    args: ["Mellow Token Cells V1", "MTCV1"],
    log: true,
  });
};
export default func;
func.tags = ['TokenCells'];