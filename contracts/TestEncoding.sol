// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultGovernance.sol";
import "./interfaces/IVaultRegistry.sol";
import "hardhat/console.sol";


contract TestEncoding {
    IProtocolGovernance.Params private data;
    address addr;

    function setDataCalldata(bytes calldata tempData) public {
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, address payable f, IVaultRegistry g) = abi.decode(tempData, (uint256, uint256, uint256, uint256, uint256, address, IVaultRegistry));
        data.maxTokensPerVault = a;
        data.governanceDelay = b;
        data.strategyPerformanceFee = c;
        data.protocolPerformanceFee = d;
        data.protocolExitFee = e;
        data.protocolTreasury = f;
        data.vaultRegistry = g;
    }

    function setDataMemory(bytes memory tempData) public {
        data = abi.decode(tempData, (IProtocolGovernance.Params));
    }

    function getData() public view returns(IProtocolGovernance.Params memory) {
        return data;
    }

    function setAddress(bytes calldata _addr) public {
        addr = abi.decode(_addr, (address));
        console.log(addr);
    }

    function getAddress() public view returns(address) {
        return addr;
    }

}
