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
import { KeyValueStoreClient } from "defender-kvstore-client"

async function main(
    signer: DefenderRelaySigner,
    provider: DefenderRelayProvider
) {
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

    const store = new KeyValueStoreClient(event);
    // await store.put('twFr', instantaneousFixedRate.toString());

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