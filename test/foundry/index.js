const ethers = require("ethers");
const fs = require("fs");
const { BigNumber, providers, constants, utils } = ethers;
const {Network, Alchemy} = require('alchemy-sdk');
const axios = require('axios');

const genericABIGenerator = (
    args,
    function_name,
    returnType = "int"
  ) => {
    let inputs = [];
    for (let i = 0; i < args.length; ++i) {
        inputs.push({name: `arg${i}`, type: args[i]});
    }

    return [
      {
        inputs: inputs,
        name: function_name,
        outputs: [
          {
            name: "output",
            type: returnType,
          },
        ],
        stateMutability: "view",
        type: "function",
      },
    ];
  };

callContract = async function(contractAddress, inputTypeList, function_name, outputType, provider, args) {
    const contract = new ethers.Contract(contractAddress, genericABIGenerator(inputTypeList, function_name, outputType), provider);
   // console.log(contract);
   // console.log(args);
    const result = await contract.functions[function_name](...args);
    return result.output;
}


main = async function () {

    require('dotenv').config();  // TO REMOVE

    let provider = new providers.AlchemyProvider("mainnet", "2hGHxl93BXAhw36CS-PytquxtQQNEPcS");
    const vaultAddress = "0x814D50FFBEE5113d54e2eD8Ea8Aaa0f578ba3FB7";

    const manager = await callContract(vaultAddress, [], "creditManager", "address", provider, []);    
    const oracle = await callContract(manager, [], "priceOracle", "address", provider, []);
    const pool = await callContract(manager, [], "pool", "address", provider, []);

    const cvx_token_address = "0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B";
    const crv_token_address = "0xD533a949740bb3306d119CC777fa900bA034cd52";
    const helper_address = "0x11aB305016d90611cF35E1A976F9cD56d6a32c41";

    const borrow_apy = await callContract(pool, [], "borrowAPY_RAY", "uint256", provider, []);
    const interest = BigNumber.from(await callContract(manager, [], "fees", "uint16", provider, []));
    const marginalFactorD9 = await callContract(vaultAddress, [], "marginalFactorD9", "uint256", provider, []);

    const percentageBorrow = borrow_apy.mul(BigNumber.from(10000).add(interest)).mul(marginalFactorD9.sub(BigNumber.from(10).pow(9))).div(BigNumber.from(10).pow(36));
    
    const convexOutputToken = await callContract(vaultAddress, [], "convexOutputToken", "address", provider, []);
    const underlying = await callContract(convexOutputToken, [], "underlying", "address", provider, []);
    const operator = await callContract(underlying, [], "operator", "address", provider, []);

    const poolId = BigNumber.from(await callContract(vaultAddress, [], "poolId", "uint256", provider, [])); 

    const lp = await callContract(operator, ["uint256"], "poolInfo", "address", provider, [poolId]);
    const rewards_contract = "0x0A760466E1B4621579a82a39CB56Dda2F4E70f03"; // call crvRewards here 

    const rew = await callContract(rewards_contract, [], "currentRewards", "uint256", provider, []);
    const sup = await callContract(rewards_contract, [], "totalSupply", "uint256", provider, []);

    let vr = BigNumber.from(0);
    const primary = await callContract(vaultAddress, [], "primaryToken", "address", provider, []);
    const deposit = await callContract(vaultAddress, [], "depositToken", "address", provider, []);

    if (primary != deposit) {
        vr = BigNumber.from(10).pow(9);
    }

    const stakingToken = await callContract(rewards_contract, [], "stakingToken", "address", provider, []);
    const rewardToken = await callContract(rewards_contract, [], "rewardToken", "address", provider, []);

    let percentageRaw = rew.mul(52).mul(10000).mul(marginalFactorD9.sub(vr)).div(sup).div(BigNumber.from(10).pow(9));
    const z = await callContract(oracle, ["uint256", "address", "address"], "convert", "uint256", provider, [BigNumber.from(10).pow(18), stakingToken, rewardToken]);

    percentageRaw = percentageRaw.mul(BigNumber.from(10).pow(18)).div(z);
    const value = await callContract(helper_address, ["uint256", "address"], "calculateEarnedCvxAmountByEarnedCrvAmount", "uint256", provider, [BigNumber.from(10).pow(18), cvx_token_address]);

    const answer = await callContract(oracle, ["uint256", "address", "address"], "convert", "uint256", provider, [value, cvx_token_address, crv_token_address]);
    percentageRaw = percentageRaw.mul(answer.add(BigNumber.from(10).pow(18))).div(BigNumber.from(10).pow(18));

    console.log(percentageRaw);
    console.log(percentageBorrow);

    let apy = percentageRaw.sub(percentageBorrow);

    const minter = await callContract(lp, [], "minter", "address", provider, []);
    const url = "https://api.curve.fi/api/getSubgraphData"
    const res = await axios.get(url);

    const list = res.data.data.poolList;
    let percentage_curve = 0;

    for (let i = 0; i < list.length; ++i) {
        if (list[i].address == minter) {
            percentage_curve = list[i].latestWeeklyApy * 100;
        } 
    }

    percentage_curve = BigNumber.from(Math.ceil(percentage_curve * marginalFactorD9 / (10**9)));
    apy = apy.add(percentage_curve);

    console.log(apy);

    

};

main();