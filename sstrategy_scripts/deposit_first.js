const ethers = require("ethers");
const aws = require("aws-sdk");
const fs = require('fs');
const { randomBytes } = require("crypto");
require('dotenv').config()
const { BigNumber, providers } = ethers;

(async() => {

	// Initialize an ethers instance
	const provider = new ethers.providers.AlchemyProvider("goerli", "2hGHxl93BXAhw36CS-PytquxtQQNEPcS");
	const depositor = new ethers.Wallet(process.env.DEPOSITOR_PK, provider);
	const admin = new ethers.Wallet(process.env.ADMIN_PK, provider);

  
	const cyclicRootVaultABIData = fs.readFileSync("cyclicRootVaultABI.txt", "utf8");
	let cyclicRootVaultABI = cyclicRootVaultABIData.toString();
	const cyclicRootVault = new ethers.Contract(
		process.env.ROOTVAULT_ADDRESS,
		cyclicRootVaultABI,
		provider
	);
	
	await (await cyclicRootVault.connect(admin).addDepositorsToAllowlist([depositor.address])).wait();

	let maxPriorityFeePerGas = BigNumber.from(
		await provider.send("eth_maxPriorityFeePerGas", [])
	  );
	let deposit = BigNumber.from(10).pow(12);


	const owethAddress = await cyclicRootVault.primaryToken();

	const owethABIData = fs.readFileSync("owethABI.txt", "utf8");
	let owethABI = owethABIData.toString();
	const oweth = new ethers.Contract(
		owethAddress,
		owethABI,
		provider
	);
	await oweth.connect(depositor).approve(process.env.ROOTVAULT_ADDRESS, deposit);
	console.log("allowance");
	console.log((await oweth.allowance(depositor.address, process.env.ROOTVAULT_ADDRESS)).toString());
	let tx = await cyclicRootVault.connect(depositor).deposit([deposit], 1, randomBytes(4), {maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	console.log(tx);
	await tx.wait();
})()
