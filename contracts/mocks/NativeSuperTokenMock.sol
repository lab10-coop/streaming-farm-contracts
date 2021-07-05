// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;

import {
    ISuperfluid,
    ISuperTokenFactory
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { NativeSuperTokenProxy } from "@superfluid-finance/ethereum-contracts/contracts/tokens/NativeSuperToken.sol";

/*
* usage:
* - create the contract
* - call selfRegister()
* - call initialize()
* - instantiate as ISuperToken
*/
contract NativeSuperTokenMock is NativeSuperTokenProxy {
    function selfRegister(ISuperfluid sf) external {
        ISuperTokenFactory factory = sf.getSuperTokenFactory();
        factory.initializeCustomSuperToken(address(this));
    }
}