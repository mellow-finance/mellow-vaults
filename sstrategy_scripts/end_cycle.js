const ethers = require("ethers");
console.log(ethers.version)
const aws = require("aws-sdk");
const fs = require('fs');
const { randomBytes } = require("crypto");
require('dotenv').config()
const { BigNumber, providers } = ethers;

(async() => {

	// Initialize an ethers instance
	const provider = new ethers.providers.AlchemyProvider("goerli", "2hGHxl93BXAhw36CS-PytquxtQQNEPcS");
	const operator = new ethers.Wallet(process.env.OPERATOR_PK, provider);
	const admin = new ethers.Wallet(process.env.ADMIN_PK, provider);
	const safe = new ethers.Wallet(process.env.SAFE_PK, provider);
  
	const sStrategyABIData = fs.readFileSync("sStrategyABI.txt", "utf8");
	let sStrategyABI = sStrategyABIData.toString();
	const sStrategy = new ethers.Contract(
		process.env.STRATEGY_ADDRESS,
		sStrategyABI,
		provider
	);

	let maxPriorityFeePerGas = BigNumber.from(
		await provider.send("eth_maxPriorityFeePerGas", [])
	);

	let res = await sStrategy.connect(operator).callStatic.endCycleMocked(safe.address, {maxFeePerGas: BigNumber.from(10).pow(9).mul(150), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	console.log(res.priceChangeD9.toNumber());
	let tx = await sStrategy.connect(operator).endCycleMocked(safe.address, {maxFeePerGas: BigNumber.from(10).pow(9).mul(150), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	await tx.wait();
})()
