import { deployments } from "hardhat";

export const setupLibraries = deployments.createFixture(async ({deployments, getNamedAccounts, ethers}, options) => {
    await deployments.fixture();
    const { tokenOwner } = await getNamedAccounts();
    const CommonLibrary = await ethers.getContractFactory("Common", tokenOwner);
    const commonLibrary = await CommonLibrary.deploy();
    return {
        tokenOwner: {
            address: tokenOwner,
            commonLibrary
        }
    }     
});


export const setupProtocolGovernance = deployments.createFixture(async ({
    deployments,
    getNamedAccounts,
    ethers,
}, _) => {
    await deployments.fixture();
    const { tokenOwner } = await getNamedAccounts();
    const ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance", tokenOwner);
    const protocolGovernance = await ProtocolGovernance.deploy();
    return {
        tokenOwner: {
            address: tokenOwner,
            protocolGovernance
        }
    }
});
