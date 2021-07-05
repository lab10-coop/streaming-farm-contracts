// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;

import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

// Mock of an UniswapV2Pair implementing a subset of IUniswapV2Pair + convenience functions
contract UniswapV2PairMock is ERC20 {
    using SafeMath for uint256;

    IERC20 public token0;
    IERC20 public token1;

    constructor(IERC20 token0_, IERC20 token1_) ERC20("mock", "MOCK") {
        token0 = token0_;
        token1 = token1_;
    }

    /*
    function mintTo(address receiver, uint256 amount) public {
        _mint(receiver, amount);
    }
    */

    // implements a maximally simple deposit logic
    function addLiquidity(uint256 amount0, uint256 amount1) public {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        uint256 liquidity = sqrt(amount0.mul(amount1));
        _mint(msg.sender, liquidity);
    }

    //
    function removeLiquidity(uint256 amount) public {
        //transferFrom(msg.sender, address(this), amount);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 amount0 = amount.mul(balance0) / totalSupply();
        uint256 amount1 = amount.mul(balance1) / totalSupply();

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        _burn(msg.sender, amount);
    }

    // copied from https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/libraries/Math.sol
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}