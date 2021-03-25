// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

interface IMarketGeneration
{
    function roundTotals(uint8 round) external view returns (uint256);
    function refPoints(address) external view returns (uint256);
    function totalRefPoints() external view returns (uint256);
    function buyRoundsCount() external view returns (uint8);
}