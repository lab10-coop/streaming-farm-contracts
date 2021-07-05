// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(uint256 initialSupply) ERC20("mock", "MOCK") {
        _mint(msg.sender, initialSupply);
    }
}