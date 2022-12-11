const ethers = require("ethers");
console.log(ethers.version)
const aws = require("aws-sdk");
const fs = require('fs');
const { randomBytes } = require("crypto");
const { BigNumber, providers } = ethers;

const GAS = (maxPriorityFee) => { return {maxFeePerGas: BigNumber.from(10).pow(9).mul(150), maxPriorityFeePerGas: maxPriorityFee, gasLimit: BigNumber.from(10).pow(6)} };

(async() => {

	// Initialize an ethers instance
	const provider = new ethers.providers.AlchemyProvider("goerli", "2hGHxl93BXAhw36CS-PytquxtQQNEPcS");
	const safe = new ethers.Wallet("3dccea3b436cc88d1ec65d0fba81c8d7952ab5d77b703a5426a529851fc16dfe", provider);

	const sStrategyAddress = "0x78F7D90A50cE5B9EBb91C5B0761136E1Cfab6dA6";
  
	
	const requestableRootAddress = "0xCf77Dea03ee0F4E42fFd9c7056daEb7C36efa152";
  
	const requestableRootABIData = fs.readFileSync("requestableRootABI.txt", "utf8");
	let requestableRootABI = requestableRootABIData.toString();
	const requestableRoot = new ethers.Contract(
		requestableRootAddress,
		requestableRootABI,
		provider
	);
	

	const owethAddress = await requestableRoot.primaryToken();

	const owethABIData = fs.readFileSync("owethABI.txt", "utf8");
	let owethABI = owethABIData.toString();
	const oweth = new ethers.Contract(
		owethAddress,
		owethABI,
		provider
	);
	let balance = await oweth.balanceOf(safe.address);
	let maxPriorityFeePerGas = BigNumber.from(
		await provider.send("eth_maxPriorityFeePerGas", [])
	  );
	let tx = await oweth.connect(safe).approve(sStrategyAddress, balance, GAS(maxPriorityFeePerGas));
	
	await tx.wait();
	console.log(tx.hash);
})()
