// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

import "./IUniswapV2Pair.sol";

interface ILiquidityLockedERC20
{
    function setLiquidityLock(IUniswapV2Pair _liquidityPair, bool _locked) external;
}