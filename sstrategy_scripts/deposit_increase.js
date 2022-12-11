const ethers = require("ethers");
const aws = require("aws-sdk");
const fs = require('fs');
const { randomBytes } = require("crypto");
require('dotenv').config()
const { BigNumber, providers } = ethers;

(async() => {
	const provider = new ethers.providers.AlchemyProvider("goerli", "2hGHxl93BXAhw36CS-PytquxtQQNEPcS");
	const depositor = new ethers.Wallet(process.env.DEPOSITOR_PK, provider);
	const admin = new ethers.Wallet(process.env.ADMIN_PK, provider);
	
	let maxPriorityFeePerGas = BigNumber.from(
		await provider.send("eth_maxPriorityFeePerGas", [])
	);
	const cyclicRootVaultABIData = fs.readFileSync("cyclicRootVaultABI.txt", "utf8");
	let cyclicRootVaultABI = cyclicRootVaultABIData.toString();
	const cyclicRootVault = new ethers.Contract(
		process.env.ROOTVAULT_ADDRESS,
		cyclicRootVaultABI,
		provider
	);

	const owethAddress = await cyclicRootVault.primaryToken();
	const owethABIData = fs.readFileSync("owethABI.txt", "utf8");
	let owethABI = owethABIData.toString();
	const oweth = new ethers.Contract(
		owethAddress,
		owethABI,
		provider
	);

	if (await cyclicRootVault.isClosed()) {
		await cyclicRootVault.connect(admin).reopen();
	}

	let depositAmount = BigNumber.from(10).pow(18).mul(30);
	// await (await oweth.connect(depositor).deposit({value: depositAmount})).wait();
	await (await oweth.connect(depositor).approve(process.env.ROOTVAULT_ADDRESS, depositAmount)).wait();

	console.log("allowance");
	console.log((await oweth.allowance(depositor.address, process.env.ROOTVAULT_ADDRESS)).toString());
	let tx = await cyclicRootVault.connect(depositor).deposit([depositAmount], 1, randomBytes(4), {maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	console.log(tx);
	await tx.wait();
})()
