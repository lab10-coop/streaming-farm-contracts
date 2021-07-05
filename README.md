# About

This repository contains Solidity contracts for a system of streaming farms.  
A _Streaming Farm_ is based on a contract which accepts specific Uniswap-V2 compliant LP tokens and rewards such stakes with a stream of _reward tokens_.  
In the current implementation, the reward token needs to be one of the tokens in the LP token pair, because the contract derives the reference value for reward calculation from the price in the LP at the time of staking.  
In the context of a staking transation, an NFT is minted to the staker and a reward stream is started to the NFT owner / staker.  
Ownership of that NFT determines ownership of the stake and thus the locked LP tokens and the reward stream.  
Whenever the NFT is transferred to a new owner, the reward stream is redirected to the new owner and the exclusive permission to close the position and withdraw the locked LP tokens handed over to the new owner.

A first version of streaming farms was deployed for MIVA LPs on xdai, with the Dapp at https://farm.minerva.digital/.  
For hackmoney2021, the contracts were extended to include a factory contract which deploys new farm instances (clones of a master contract) with configurable LP token and reward token and on-chain generation of metadata (JSON and SVG).  
With this architecture, a single NFT contract is shared by all farms instantiated through the factory. Whenever a new farm is created, it's also given permission to mint new tokens. At the same time, the NFT contract delegates calls to `tokenURI` to the minting contract and also allows only the minting contract to burn that token. This gives individual farm contracts full ownership of the tokens it creates.

Tests are not yet included as the adaptation of the existing tests to the new architecture is still work in progress.  
A CLI demo can be seen [here](https://youtu.be/YMEG1kiaFAI?t=59).