// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @notice Library for emulating evm scripts
contract EVMLibrary {
    function execute(bytes memory code, bytes memory data) internal view returns (uint256 res) {
        uint16 pc;
        uint8 top;
        uint256[] memory stack = new uint256[](16);
        while (pc < code.length) {
            (pc, top, res) = _doInstruction(code, data, stack, pc, top);
            // type(uint256).max means execution continues
            if (res != type(uint256).max) {
                return res;
            }
        }
        return 0;
    }

    function _doInstruction(
        bytes memory code,
        bytes memory data,
        uint256[] memory stack,
        uint16 pc,
        uint8 top
    )
        private
        view
        returns (
            uint16 pcUpdated,
            uint8 topUpdated,
            uint256 res
        )
    {
        res = type(uint256).max;
        uint8 instruction = uint8(code[pc]);
        if (instruction == 0) {
            return (pc + 1, top, 0);
        }
        if (instruction < 0x10) {
            // ADD
            if (instruction == 0x1) {
                stack[top - 2] = stack[top - 2] + stack[top - 1];
            }
            // MUL
            else if (instruction == 0x2) {
                stack[top - 2] = stack[top - 2] * stack[top - 1];
            }
            // SUB
            else if (instruction == 0x3) {
                stack[top - 2] = stack[top - 2] - stack[top - 1];
            }
            // DIV
            else if (instruction == 0x4) {
                stack[top - 2] = stack[top - 2] / stack[top - 1];
            }
            // MOD
            else if (instruction == 0x6) {
                stack[top - 2] = stack[top - 2] % stack[top - 1];
            }
            stack[top - 1] = 0;
            pcUpdated = pc + 1;
            topUpdated = top - 1;
            return (pcUpdated, topUpdated, res);
        }
        if (instruction < 0x19) {
            // LT
            if (instruction == 0x10) {
                stack[top - 2] = stack[top - 2] < stack[top - 1] ? 1 : 0;
            }
            // GT
            else if (instruction == 0x11) {
                stack[top - 2] = stack[top - 2] > stack[top - 1] ? 1 : 0;
            }
            // EQ
            else if (instruction == 0x14) {
                stack[top - 2] = stack[top - 2] == stack[top - 1] ? 1 : 0;
            }
            // AND
            else if (instruction == 0x16) {
                stack[top - 2] = stack[top - 2] & stack[top - 1];
            }
            // OR
            else if (instruction == 0x17) {
                stack[top - 2] = stack[top - 2] | stack[top - 1];
            }
            // XOR
            else if (instruction == 0x18) {
                stack[top - 2] = stack[top - 2] ^ stack[top - 1];
            }

            stack[top - 1] = 0;
            pcUpdated = pc + 1;
            topUpdated = top - 1;
            return (pcUpdated, topUpdated, res);
        }
        if (instruction == 0x19) {
            stack[top - 1] = ~stack[top - 1];
            topUpdated = top;
            pcUpdated = pc + 1;
            return (pcUpdated, topUpdated, res);
        }
        if (instruction < 0x30) {
            // SHL
            if (instruction == 0x1B) {
                stack[top - 2] = stack[top - 1] << stack[top - 2];
            }
            // SHR
            else if (instruction == 0x1C) {
                stack[top - 2] = stack[top - 1] << stack[top - 2];
                // SHA 3
            } else if (instruction == 0x20) {
                uint256 kck;
                uint256 offset = stack[top - 2];
                uint256 length = stack[top - 1];
                assembly {
                    let off := add(add(data, 0x20), offset)
                    kck := keccak256(off, length)
                }
                stack[top - 2] = kck;
            }
            stack[top - 1] = 0;
            pcUpdated = pc + 1;
            topUpdated = top - 1;
            return (pcUpdated, topUpdated, res);
        }
        if (instruction < 0x50) {
            // ADDRESS
            if (instruction == 0x30) {
                stack[top] = uint256(uint160(address(this)));
                // ORIGIN
            } else if (instruction == 0x32) {
                stack[top] = uint256(uint160(tx.origin));
                // CALLER
            } else if (instruction == 0x33) {
                stack[top] = uint256(uint160(msg.sender));
            }
            // TIMESTAMP
            else if (instruction == 0x42) {
                stack[top] = uint256(uint160(block.timestamp));
                // NUMBER
            } else if (instruction == 0x43) {
                stack[top] = uint256(uint160(block.number));
                // NUMBER
            } else if (instruction == 0x46) {
                uint256 chain;
                assembly {
                    chain := chainid()
                }
                stack[top] = chain;
            }
            pcUpdated = pc + 1;
            topUpdated = top + 1;
            return (pcUpdated, topUpdated, res);
        }
    }
}
