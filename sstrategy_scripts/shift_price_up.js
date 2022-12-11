const ethers = require("ethers");
const aws = require("aws-sdk");
const fs = require('fs');
const { randomBytes } = require("crypto");
require('dotenv').config()
const { BigNumber, providers } = ethers;

(async() => {

	// Initialize an ethers instance
	const provider = new ethers.providers.AlchemyProvider("goerli", "2hGHxl93BXAhw36CS-PytquxtQQNEPcS");
	const arbitrager = new ethers.Wallet(process.env.DEPOSITOR_PK, provider);

	const uniV3PoolABIData = fs.readFileSync("uniV3PoolABI.txt", "utf8");
	let uniV3PoolABI = uniV3PoolABIData.toString();
	const indexPool = new ethers.Contract(
		process.env.INDEXPOOL_ADDRESS,
		uniV3PoolABI,
		provider
	);

	const swapRouterABIData = fs.readFileSync("swapRouterABI.txt", "utf8");
	let swapRouterABI = swapRouterABIData.toString();
	const swapRouter = new ethers.Contract(
		process.env.SWAPROUTER_ADDRESS,
		swapRouterABI,
		provider
	);

	const erc20TokenABIData = fs.readFileSync("erc20TokenABI.txt", "utf8");
	let erc20TokenABI = erc20TokenABIData.toString();
	const ousdc = new ethers.Contract(
		process.env.OUSDC_ADDRESS,
		erc20TokenABI,
		provider
	);
	
	let slot = await indexPool.slot0();
	let sqrtPriceX96 = slot["sqrtPriceX96"];
	let priceWas = sqrtPriceX96.mul(sqrtPriceX96).mul(1000000000000000).div(BigNumber.from(2).pow(192));
	console.log(priceWas.toString());
	console.log(slot["tick"].toString());
	let swapAmount = await ousdc.balanceOf(arbitrager.address);
	let maxPriorityFeePerGas = BigNumber.from(
		await provider.send("eth_maxPriorityFeePerGas", [])
	  );
	
	await ousdc.connect(arbitrager).approve(swapRouter.address, swapAmount);

	let tx = await swapRouter.connect(arbitrager).exactInputSingle({
		tokenIn: process.env.OUSDC_ADDRESS,
		tokenOut: process.env.OWETH_ADDRESS,
		fee: 3000,
		recipient: arbitrager.address,
		deadline: BigNumber.from(10).pow(30),
		amountIn: swapAmount,
		amountOutMinimum: 0,
		sqrtPriceLimitX96: 0}, {maxFeePerGas: BigNumber.from(10).pow(9).mul(200), maxPriorityFeePerGas: maxPriorityFeePerGas, gasLimit: BigNumber.from(10).pow(6)});
	
	await tx.wait();

	slot = await indexPool.slot0();
	sqrtPriceX96 = slot["sqrtPriceX96"];
	let priceNext = sqrtPriceX96.mul(sqrtPriceX96).mul(1000000000000000).div(BigNumber.from(2).pow(192));

	console.log(priceNext.toString());  
	console.log(slot["tick"].toString());

	console.log("Price x" + Number(priceNext) / Number(priceWas));
})()
