// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

interface IMarketDistribution
{
    function distributionComplete() external view returns (bool);
    function claimRefRewards(address to, uint256 refShare) external;
    
    function distribute() external;
    function claim(address to, uint256 contribution, uint8 round) external;
    function generationEndTime() external view returns (uint256); 
    function vestingEnd() external view returns (uint256);
}