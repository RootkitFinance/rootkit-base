// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

interface IMarketDistribution
{
    function distributionComplete() external view returns (bool);
    function generationEndTime() external view returns (uint256); 
    function vestingEnd() external view returns (uint256);
    function distribute() external;        
    function claim(address account) external;
    function claimReferralRewards(address account, uint256 refShare) external;
}