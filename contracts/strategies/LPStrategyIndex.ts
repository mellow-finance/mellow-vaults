import { ethers } from "ethers";
import {
    DefenderRelaySigner,
    DefenderRelayProvider,
} from "defender-relay-client/lib/ethers";
import {
    RelayerParams,
    Relayer,
    RelayerModel,
} from "defender-relay-client/lib/relayer";

// Import a dependency not present in the autotask environment which will be included in the js bundle
import { GraphQLClient, gql } from "graphql-request";

async function main(
    signer: DefenderRelaySigner,
    provider: DefenderRelayProvider
) {

    const fixedRateQueryString = `
    {
        VAMMPriceChange(first: 7, orderBy: timestamp, orderDirection: desc) {
            id,
            timestamp,
            tick
        }
    }`;

    function convertTickToRate(tick: number) {
        // rate = -log_1.0001(tick)
        const rate = -Math.log(tick) / Math.log(1.0001);
        return rate
    }

    // Fetch the last 7 days worth of fixed rates from the subgraph
    async function getHistoricalTicks(): Promise<number[]> {
        const endpoint =
            "https://api.thegraph.com/subgraphs/name/voltzprotocol/mainnet-v1";
        const graphQLClient = new GraphQLClient(endpoint);

        const data = await graphQLClient.request(fixedRateQueryString);

        const tickJSON = JSON.parse(JSON.stringify(data, undefined, 2));

        const tickList = [];
        for (let i = 0; i < tickJSON.length; i++) {
            tickList.push(tickJSON.VAMMPriceChange[i].tick);
        }

        return tickList;
    }

    // Calculate the average APR over the last 7 days
    async function calculateAverageAPR() {
        const historicalTicks = await getHistoricalTicks();

        // Calculate the average tick
        const averageTick = historicalTicks.reduce((partialSum, b) => partialSum + b, 0) / historicalTicks.length;

        // Convert average tick to average APR
        const averageAPR = convertTickToRate(averageTick);

        return averageAPR;
    }


    
    // 1. Instantiate the address and abi for the strategy contract
    const lpStrategyAddress = '';
    const lpStrategyABI = '';

    // 2. Create an instance of the lpStrategy contract
    const lpStrategy = new ethers.Contract(
        lpStrategyAddress,
        lpStrategyABI,
        signer
    );

    // 3. Call the rebalanceCheck function
    const rebalanceCheckTx = await lpStrategy.rebalanceCheck();
    await rebalanceCheckTx.wait();

    // 4. Call the rebalance function if the rebalanceCheck function returns true
    if (rebalanceCheckTx) {
        const rebalanceTx = await lpStrategy.rebalance();
        await rebalanceTx.wait();
    } else {
        console.log('No rebalance required');
    }

} // Ending of the main function

// ------------------ DO NOT MODIFY ANYTHING BELOW THIS LINE ------------------
// Entrypoint for the Autotask
export async function handler(credentials: RelayerParams, event) { // the type of event is any but might need to change that
    const provider = new DefenderRelayProvider(credentials);
    const signer = new DefenderRelaySigner(credentials, provider, {
        speed: "safeLow",
    });
    const relayer = new Relayer(credentials);
    const info: RelayerModel = await relayer.getRelayer();
    console.log(`Relayer address is ${info.address}`);

    await main(signer, provider);
}

// Exported for running locally
exports.main = main;

// Typescript type definitions
type EnvInfo = {
    RELAY_API_KEY: string;
    RELAY_API_SECRET: string;
};

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
    require("dotenv").config();
    const { RELAY_API_KEY: apiKey, RELAY_API_SECRET: apiSecret } =
        process.env as EnvInfo;
    handler({ apiKey, apiSecret })
        .then(() => process.exit(0))
        .catch((error: Error) => {
            console.error(error);
            process.exit(1);
        });
}