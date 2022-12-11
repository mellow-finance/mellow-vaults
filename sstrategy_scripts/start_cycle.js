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
	
	let squeethVaultAddress = await sStrategy.squeethVault();

	const squeethVaultABIData = fs.readFileSync("squeethVaultABI.txt", "utf8");
	let squeethVaultABI = squeethVaultABIData.toString();
	const squeethVault = new ethers.Contract(
		squeethVaultAddress,
		squeethVaultABI,
		provider
	);
	
	let currentPrice = await squeethVault.twapIndexPrice();
	console.log(currentPrice.toString());
	let maxPriorityFeePerGas = BigNumber.from(
		await provider.send("eth_maxPriorityFeePerGas", [])
	);


	const owethAddress = await squeethVault.weth();
	const owethABIData = fs.readFileSync("owethABI.txt", "utf8");
	let owethABI = owethABIData.toString();
	const oweth = new ethers.Contract(
		owethAddress,
		owethABI,
		provider
	);
	
	let cyclicRootVaultAddress = await sStrategy.rootVault(); 

	const cyclicRootVaultABIData = fs.readFileSync("cyclicRootVaultABI.txt", "utf8");
	let cyclicRootVaultABI = cyclicRootVaultABIData.toString();
	const cyclicRootVault = new ethers.Contract(
		cyclicRootVaultAddress,
		cyclicRootVaultABI,
		provider
	);

	if (await cyclicRootVault.isClosed()) {
		await cyclicRootVault.connect(admin).reopen();
	}


	let tx = await sStrategy.connect(operator).startCycleMocked(currentPrice,  BigNumber.from(10).pow(18).mul(50), safe.address, false, {maxFeePerGas: BigNumber.from(10).pow(9).mul(150), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	await tx.wait();
	console.log(tx.hash);

	let safeAmount = await oweth.balanceOf(safe.address);
	await oweth.connect(safe).approve(squeethVault.address, safeAmount);
})()
