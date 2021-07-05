// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;
pragma abicoder v2;

import { IStreamingFarm } from "./IStreamingFarm.sol";
import { FarmNFT, IFarmNFTOwner } from "./FarmNFT.sol";

import { IConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {
    ISuperfluid,
    ISuperToken,
    ISuperApp
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "./StringLib.sol";

import { IFarmFactory } from "./FarmFactory.sol";

import './FarmNFTSVG.sol';
import 'base64-sol/base64.sol';

/*
* Mints NFTs for UniswapV2Pair tokens.
* Opens a reward stream to the NFT owner.
* Progressive reward rate depending on NFT age, to be updated by explicit calls.
* Also works with generic NFTs not designed with such functionality in mind.
*/
contract StreamingFarm is Initializable, IStreamingFarm, IFarmNFTOwner, Ownable {
    using Strings for uint256;

    IUniswapV2Pair public override stakingToken;
    ISuperToken public override rewardToken;
    IFarmFactory internal factory;
    //farmNFT() public override farmNFT();

    ISuperfluid internal _sfHost;
    IConstantFlowAgreementV1 internal _cfa;

    struct NFTProps {
        uint256 stakingTokenAmount; // set once
        uint256 referenceValue; // set once
        uint64 creationTimestamp; // set once
        uint8 currentLevel;
    }

    // properties per NFT id
    mapping(uint256 => NFTProps) _nftProps;

    uint32 public constant DAYS = 3600*24;
    uint64 public constant INTEREST_GRANULARITY = uint64(7)*DAYS*1E6;

    // source for the values: https://docs.google.com/spreadsheets/d/1SHdVNHEtr60MQXsgbA4E621IPKK5DOhux23DrNjLd5o
    // minAge, interest per week per million
    // both array elements need to be monotonically increasing, element [0][0] needs to be 0.

    uint32[][] _rewardSchedule;

    uint256 _maxAggregateFlowRate;
    uint256 _currentMaxAchievableAggregateFlowRate;

    // ================== Admin interface =================

    //constructor(ISuperfluid sfHost, IUniswapV2Pair stakingToken_, ISuperToken rewardToken_, uint256 maxAggrFlowRate_) {
    function initialize(ISuperfluid sfHost, IUniswapV2Pair stakingToken_, ISuperToken rewardToken_, uint256 maxAggrFlowRate_)
        public initializer
    {
        factory = IFarmFactory(msg.sender);

        _sfHost = ISuperfluid(sfHost);
        _maxAggregateFlowRate = maxAggrFlowRate_;
        address cfaAddr = address(
            _sfHost.getAgreementClass(keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1"))
        );
        _cfa = IConstantFlowAgreementV1(cfaAddr);

        stakingToken = stakingToken_;
        rewardToken = rewardToken_;

        require(
            stakingToken.token0() == address(rewardToken) || stakingToken.token1() == address(rewardToken),
                "StreamingFarm: rewardToken not a component of the LP token"
        );
        _rewardSchedule = [
            [0*DAYS, 2940], // level 1: day 0+, 0.294%
            [7*DAYS, 6190], // level 2: day 7+
            [30*DAYS, 9780], // level 3: day 30+
            [90*DAYS, 15870], // level 4: day 90+
            [180*DAYS, 22940], // level 5: day 180+
            [360*DAYS, 34160] // level 6: day 360+
        ];
        assert(_rewardSchedule[0][0] == 0); // required for loop safety
    }

    // allows the owner to withdraw any contract owned ERC-20 tokens except of stake tokens
    function withdrawERC20Tokens(IERC20 token, address receiver, uint256 amount) public onlyOwner {
        require(address(token) != address(stakingToken), "StreamingFarm: withdrawal of stake tokens forbidden");
        token.transfer(receiver, amount);
    }

    function setMaxAggregateFlowrate(uint256 newValue) public onlyOwner {
        require(newValue >= _currentMaxAchievableAggregateFlowRate, "StreamingFarm: value below current usage");
        _maxAggregateFlowRate = newValue;
    }

    // ================== IStreamingFarm =================

    function stake(uint256 amount) external override returns(uint256) {
        // see https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2Pair.sol#L134
        uint256 refVal = amount * rewardToken.balanceOf(address(stakingToken)) / stakingToken.totalSupply();

        // check if there's still enough capacity
        uint256 maxAchievableFlowRate = refVal * _maxReward() / INTEREST_GRANULARITY;
        require(
            _currentMaxAchievableAggregateFlowRate + maxAchievableFlowRate <= _maxAggregateFlowRate,
                "StreamingFarm: not enough flowrate capacity left"
        );
        _currentMaxAchievableAggregateFlowRate += maxAchievableFlowRate;

        // fetch the staking tokens from the sender - requires prior approval by sender, will fail otherwise
        stakingToken.transferFrom(msg.sender, address(this), amount);
        uint256 nftId = farmNFT().mint(msg.sender);

        _nftProps[nftId] = NFTProps({
            creationTimestamp: uint64(block.timestamp),
            stakingTokenAmount: amount,
            referenceValue: refVal,
            currentLevel: uint8(1)
        });
        int96 flowRate = _getFlowRate(refVal, 1);
        require(flowRate > 0, "StreamingFarm: stake too small");
        _updateStream(msg.sender, flowRate);

        emit Stake(msg.sender, nftId, amount, refVal);
        emit RewardStream(nftId, msg.sender, uint256(flowRate));
        return nftId;
    }

    function unstake(uint256 nftId) external override {
        require(farmNFT().ownerOf(nftId) == msg.sender, "StreamingFarm: not your NFT");
        int96 expectedCurrentFlowrate = _getFlowRate(_nftProps[nftId].referenceValue, _nftProps[nftId].currentLevel);
        _updateStream(farmNFT().ownerOf(nftId), -expectedCurrentFlowrate);
        stakingToken.transfer(msg.sender, _nftProps[nftId].stakingTokenAmount);
        farmNFT().burn(nftId);
        delete _nftProps[nftId];
        emit Unstake(msg.sender, nftId);
    }

    // TODO: should we permission this to the NFT owner?
    function upgradeLevel(uint256 nftId) public override {
        _updateRewardStream(nftId, farmNFT().ownerOf(nftId), false);
    }

    function farmNFT() public view override returns(FarmNFT) {
        return factory.farmNFT();
    }

    function rewardSchedule() external view override returns(uint32[][] memory) {
        return _rewardSchedule;
    }

    function maxAggregateFlowrate() external view override returns(uint256) {
        return _maxAggregateFlowRate;
    }

    function remainingAvailableFlowrate() external view override returns(uint256) {
        return _maxAggregateFlowRate - _currentMaxAchievableAggregateFlowRate;
    }

    function getNFTInfo(uint256 nftId) external view override
    returns(
        uint64 creationTimestamp,
        uint256 stakeAmount,
        uint256 referenceValue,
        address currentOwner,
        uint8 setLevel,
        uint8 availableLevel,
        uint64 nextLevelTimestamp)
    {
        require(_nftProps[nftId].creationTimestamp > 0, "StreamingFarm: unknown NFT");
        creationTimestamp = _nftProps[nftId].creationTimestamp;
        stakeAmount = _nftProps[nftId].stakingTokenAmount;
        referenceValue = _nftProps[nftId].referenceValue;
        currentOwner = farmNFT().ownerOf(nftId);
        setLevel = _nftProps[nftId].currentLevel;
        availableLevel = _getAvailableLevel(nftId);
        // since level count starts at 1, it points to the index of the next level (if not already in max level)
        nextLevelTimestamp = availableLevel >= _rewardSchedule.length ? 0
        : creationTimestamp + _rewardSchedule[availableLevel][0];
    }

    function canUpgradeLevel(uint256 nftId) public view override returns (bool){
        require(_nftProps[nftId].creationTimestamp != 0, "StreamingFarm: unknown NFT");
        int96 availFR = _getFlowRate(_nftProps[nftId].referenceValue, _getAvailableLevel(nftId));
        int96 curFR = _getFlowRate(_nftProps[nftId].referenceValue, _nftProps[nftId].currentLevel);
        return availFR != curFR;
    }

    // ================== IfarmNFT()Owner =================

    function onNFTTransfer(address from, address/* to*/, uint256 tokenId) public override {
        require(msg.sender == address(farmNFT()), "StreamingFarm: forbidden sender");
        _updateRewardStream(tokenId, from, true);
    }

    function getNftTokenURI(uint256 tokenId) external view override returns (string memory uri) {
        // inspiration: https://github.com/Uniswap/uniswap-v3-periphery/blob/v1.0.0/contracts/libraries/NFTDescriptor.sol
        string memory imageB64 = Base64.encode(bytes(FarmNFTSVG.getYinYangSVG()));
        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{',
                                '"name":"Minerva Farm Position",',
                                '"description": "This position represents ',
                                    Strings.toString(_nftProps[tokenId].stakingTokenAmount),
                                    ' LP tokens currently staked in farm ',
                                    Strings.toHexString(uint256(address(this))),
                                    '. TODO: more details",',
                                '"image":"data:image/svg+xml;base64,',
                                    imageB64,
                            '"}'
                        )
                    )
                )
            )
        );

        //return FarmNFTSVG.getSVG();
    }

    /*
    string constant TOKEN_URI_BASE = "https://miva.minerva.digital/farm/v1/";
    function getNftTokenURI(uint256 tokenId) external view override returns (string memory uri) {
        return string(abi.encodePacked(
            TOKEN_URI_BASE,
            Strings.toHexString(uint256(address(this))),
            "/",
            tokenId.toString()
        ));
    }
    */

    // ================== internal interface =================

    // makes sure the reward stream goes to the NFT owner with correct flowrate
    // no caller restriction
    function _updateRewardStream(uint256 nftId, address prevOwner, bool forceOwnerChange) internal {
        require(_nftProps[nftId].creationTimestamp != 0, "StreamingFarm: unknown NFT");
        int96 expectedCurrentFlowRate = _getFlowRate(_nftProps[nftId].referenceValue, _nftProps[nftId].currentLevel);
        uint8 newLevel = _getAvailableLevel(nftId);
        int96 targetFlowRate = _getFlowRate(_nftProps[nftId].referenceValue, newLevel);
        if (farmNFT().ownerOf(nftId) != prevOwner || forceOwnerChange) {
            // reduce stream to previous owner
            _updateStream(prevOwner, -expectedCurrentFlowRate);
            // start stream to new owner
            _updateStream(farmNFT().ownerOf(nftId), targetFlowRate);
        } else {
            // increase stream to existing owner
            _updateStream(farmNFT().ownerOf(nftId), targetFlowRate - expectedCurrentFlowRate);
        }
        // TODO: does this cause an unnecessary extra SSTORE?
        _nftProps[nftId].currentLevel = newLevel;
        emit RewardStream(nftId, farmNFT().ownerOf(nftId), uint256(targetFlowRate));
    }

    function _getFlowRate(uint256 referenceValue, uint8 level) internal view returns(int96) {
        return int96(referenceValue * _getInterestByLevel(level) / INTEREST_GRANULARITY);
    }

    // returns the max level currently available for this NFT or 0 for unknown NFTs
    // reminder: "level" starts counting at 1
    function _getAvailableLevel(uint256 nftId) public view returns(uint8) {
        if (_nftProps[nftId].creationTimestamp == 0) {
            return 0;
        }
        uint256 age = block.timestamp - _nftProps[nftId].creationTimestamp;
        // rewardSchedule[0][0] MUST be 0 for this loop to work as expected!
        for (uint i = _rewardSchedule.length-1; i >= 0; i--) {
            if (age >= _rewardSchedule[i][0]) {
                return uint8(i+1);
            }
        }
        return 0; // should never be reached
    }

    function _getInterestByLevel(uint8 level) public view returns (uint) {
        require(level >= 1 && level <= _rewardSchedule.length+1, "StreamingFarm: invalid level");
        return _rewardSchedule[level-1][1];
    }

    function _updateStream(address receiver, int96 deltaFlowRate) internal {
        (uint256 timestamp, int96 curFlowRate,,) = _cfa.getFlow(rewardToken, address(this), receiver);
        int96 flowRate = curFlowRate + deltaFlowRate; // note that deltaFlowRate may be negative, making this 0 or neg.
        if (timestamp == 0) { // no pre-existing stream
            if (flowRate > 0) {
                _sfHost.callAgreement(
                    _cfa,
                    abi.encodeWithSelector(
                        _cfa.createFlow.selector,
                        rewardToken,
                        receiver,
                        flowRate,
                        new bytes(0)
                    ),
                    "0x"
                );
            }
        } else { // pre-existing stream
            if (flowRate > 0) {
                _sfHost.callAgreement(
                    _cfa,
                    abi.encodeWithSelector(
                        _cfa.updateFlow.selector,
                        rewardToken,
                        receiver,
                        flowRate,
                        new bytes(0)
                    ),
                    "0x"
                );
            } else /* if (flowRate == 0) */ {
                _sfHost.callAgreement(
                    _cfa,
                    abi.encodeWithSelector(
                        _cfa.deleteFlow.selector,
                        rewardToken,
                        address(this),
                        receiver,
                        new bytes(0)
                    ),
                    "0x"
                );
            }/* else {
                assert(false); // should be unreachable
            }*/
        }
    }

    function _maxReward() internal view returns(uint32) {
        return _rewardSchedule[_rewardSchedule.length-1][1];
    }
}