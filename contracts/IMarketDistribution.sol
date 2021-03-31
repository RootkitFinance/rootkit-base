// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

interface IMarketDistribution
{
    function distributionComplete() external view returns (bool);
    function vestingPeriodStartTime() external view returns (uint256); 
    function vestingPeriodEndTime() external view returns (uint256);
    function distribute() external;        
    function claim(address account) external;
    function claimReferralRewards(address account, uint256 refShare) external;
}