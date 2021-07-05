// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;

import "./StreamingFarm.sol";
import { FarmNFT, IFarmNFTOwner } from "./FarmNFT.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
//import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import { ISuperfluid } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface IFarmFactory {
    event NewFarm(address indexed farmAddress, address indexed creator);

    function createFarm(IUniswapV2Pair stakingToken, ISuperToken rewardToken, uint256 maxAggrFlowRate) external returns (address);
    function farmNFT() external view returns (FarmNFT);
}

contract FarmFactory is /* TransparentUpgradeableProxy, */IFarmFactory {
    address public immutable farmImplementation;
    ISuperfluid internal _sfHost;
    FarmNFT public override farmNFT;

    constructor(ISuperfluid sfHost) public {
        _sfHost = sfHost;
        farmImplementation = address(new StreamingFarm());
        farmNFT = new FarmNFT();
    }

    // TODO: add rewardSchedule
    function createFarm(IUniswapV2Pair stakingToken, ISuperToken rewardToken, uint256 maxAggrFlowRate) external override returns (address) {
        address instance = Clones.clone(farmImplementation);
        StreamingFarm(instance).initialize(_sfHost, stakingToken, rewardToken, maxAggrFlowRate);
        farmNFT.addMinter(instance);
        emit NewFarm(instance, msg.sender);
        return instance;
    }
}