// SPDX-License-Identifier: J-J-J-JENGA!!!
pragma solidity ^0.7.4;


import "../IERC20.sol";
import "../SafeERC20.sol";
import "../RootedToken.sol";
import "../IMarketDistribution.sol";
import "../IMarketGeneration.sol";

contract MarketDistributionTest is IMarketDistribution
{
    using SafeERC20 for IERC20;

    RootedToken immutable rootedToken;
    IERC20 immutable baseToken;

    mapping (address => uint256) public claimCallAmount;
    mapping (address => uint256) public claimReferralBonusCallAmount;
    bool public override distributionComplete;
    IMarketGeneration public marketGeneration; 

    constructor(RootedToken _rootedToken, IERC20 _baseToken)
    {
        rootedToken = _rootedToken;
        baseToken = _baseToken;
    }

    function distribute() public override 
    { 
        require (!distributionComplete, "Already complete");
        marketGeneration = IMarketGeneration(msg.sender);
        distributionComplete = true;
        baseToken.safeTransferFrom(msg.sender, address(this), baseToken.balanceOf(msg.sender));
    }

    function claim(address account) public override
    {
        require (distributionComplete, "Not complete");
        claimCallAmount[account] = marketGeneration.totalContribution(account);
    }

    function claimReferralRewards(address account, uint256 referralShare) public override
    {
        require (distributionComplete, "Not complete");
        claimReferralBonusCallAmount[account] = referralShare;
    }

    function generationEndTime() public override view returns (uint256) 
    { 
        return block.timestamp; 
    }

    function vestingEnd() public override view returns (uint256) 
    { 
        return block.timestamp; 
    }
}