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
	const depositor = new ethers.Wallet(process.env.DEPOSITOR_PK, provider);
	const operator = new ethers.Wallet(process.env.OPERATOR_PK, provider);
	const admin = new ethers.Wallet(process.env.ADMIN_PK, provider);
	const safe = new ethers.Wallet(process.env.SAFE_PK, provider);

	const cyclicRootVaultAddress = process.env.ROOTVAULT_ADDRESS;
	const cyclicRootVaultABIData = fs.readFileSync("cyclicRootVaultABI.txt", "utf8");
	let cyclicRootVaultABI = cyclicRootVaultABIData.toString();
	const cyclicRootVault = new ethers.Contract(
		cyclicRootVaultAddress,
		cyclicRootVaultABI,
		provider
	);

	const squeethVaultAddress = await cyclicRootVault.cyclableVault();
	const squeethVaultABIData = fs.readFileSync("squeethVaultABI.txt", "utf8");
	let squeethVaultABI = squeethVaultABIData.toString();
	const squeethVault = new ethers.Contract(
		squeethVaultAddress,
		squeethVaultABI,
		provider
	);

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

	let lp = await cyclicRootVault.balanceOf(depositor.address);
	console.log(lp);

	let tx = await cyclicRootVault.connect(depositor).registerWithdrawal(lp, {maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	await tx.wait();

	if (!(await squeethVault.totalCollateral()).eq(0)) {
		try {
			tx = await sStrategy.connect(operator).endCycleMocked(safe.address, {maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
			await tx.wait();
		} catch (exception) {
			tx = await cyclicRootVault.connect(admin).shutdown({maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
			await tx.wait();	
			tx = await sStrategy.connect(operator).endCycleMocked(safe.address, {maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
			await tx.wait();
		}
	} 

	tx = await cyclicRootVault.connect(admin).invokeExecution({maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	await tx.wait();

	tx = await cyclicRootVault.connect(depositor).withdraw(depositor.address, [randomBytes(4), randomBytes(4)], {maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)})
	await tx.wait();
})()
