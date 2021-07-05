// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;
pragma abicoder v2;

import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { FarmNFT } from "./FarmNFT.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface IStreamingFarm {
    /// @dev emitted when a new stake is added to the farm
    event Stake(address indexed owner, uint256 indexed nftId, uint256 amount, uint256 referenceValue);

    /// @dev emitted when a stake is removed from the farm
    event Unstake(address indexed owner, uint256 indexed nftId);

    /// @dev emitted when the reward stream of a stake changes receiver or flowRate
    event RewardStream(uint256 indexed nftId, address indexed receiver, uint256 flowRate);

    /// @dev Token staked in the farm. Staking needs to happen through the stake() method.
    function stakingToken() external view returns(IUniswapV2Pair);

    /// @dev Token streamed to stake owners as reward. Component of the LP token pair.
    function rewardToken() external view returns(ISuperToken);

    /// @dev NFT token contract owner by the farm (as long as the farm is active).
    function farmNFT() external view returns(FarmNFT);

    /// @dev the reward schedule configured for the farm
    /// @return a 2-dimensional array with the first element being the min age in seconds for reaching that level
    /// and the second element being the interest per week per million of reference value.
    /// note that level 1 corresponds to index 0 of the schedule.
    function rewardSchedule() external view returns(uint32[][] memory);

    /// @return the max flowrate the farm is allowed to reach (sum of all outgoing reward streams).
    /// This is enforced for the "worst case scenario" of all stakes reaching the max level.
    function maxAggregateFlowrate() external view returns(uint256);

    /// @return the flowrate available before reaching the max allowed aggregated flowrate
    function remainingAvailableFlowrate() external view returns(uint256);

    /// @dev Fetches amount of LP tokens from the sender, then mints an NFT and starts a reward stream to the sender.
    /// Uses ERC20.transferFrom() to fetch the LP tokens, the sender thus needs to approve beforehand.
    /// The id of the minted NFT is provided in the emitted 'Stake' event. It uniquely identifies this stake
    /// and is needed for all further interactions.
    /// @return nftId The id of the NFT minted representing the stake - relevant if triggered from a contract.
    /// Throws if the given amount of stake tokens can't be fetched or if the reward stream can't be opened
    /// or if the farm has been shut down or if adding the stake could lead to exceed the max. aggregate flowrate.
    function stake(uint256 amount) external returns(uint256 nftId);

    /// @dev Burns the NFT, stops the reward stream and returns the associated LP tokens.
    /// Unstaking does not affect other stakes the same sender account may have in the system.
    /// The caller needs to be the NFT owner which may or may not be the same account having minted the NFT.
    function unstake(uint256 nftId) external;

    /// @dev Returns information about current and future set and achievable rewards for an NFT
    /// @return creationTimestamp Timestamp of NFT creation
    /// @return stakeAmount Amount of LP tokens staked
    /// @return referenceValue Amount of tokens the stake represented at the time of staking
    /// @return currentOwner The current owner of the NFT
    /// @return setLevel The currently set reward level
    /// @return availableLevel The highest reward level currently available. Can be equal or greater than setLevel
    /// @return nextLevelTimestamp The timestamp when the next level (availableLevel + 1) is unlocked.
    /// If nextLevelTimestamp is 0, availableLevel is already the highest level.
    function getNFTInfo(uint256 nftId) external view returns(uint64 creationTimestamp, uint256 stakeAmount, uint256 referenceValue, address currentOwner, uint8 setLevel, uint8 availableLevel, uint64 nextLevelTimestamp);

    /// @return true if the reward level for the given NFT can be upgraded
    function canUpgradeLevel(uint256 nftId) external view returns(bool);

    /// @dev Upgrades the reward level to the highest currently available. This is permissionless.
    function upgradeLevel(uint256 nftId) external;
}