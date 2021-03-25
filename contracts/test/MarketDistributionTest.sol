// SPDX-License-Identifier: J-J-J-JENGA!!!
pragma solidity ^0.7.4;


import "../IERC20.sol";
import "../SafeERC20.sol";
import "../RootedToken.sol";
import "../IMarketDistribution.sol";

contract MarketDistributionTest is IMarketDistribution
{
    using SafeERC20 for IERC20;

    RootedToken immutable rootedToken;
    IERC20 immutable baseToken;

    mapping (address => mapping (uint8 => uint256)) public claimCallAmount;
    mapping (address => uint256) public claimRefBonusCallAmount;
    bool public override distributionComplete;

    constructor(RootedToken _rootedToken, IERC20 _baseToken)
    {
        rootedToken = _rootedToken;
        baseToken = _baseToken;
    }

    function distribute() public override 
    { 
        require (!distributionComplete, "Already complete");
        distributionComplete = true;
        baseToken.safeTransferFrom(msg.sender, address(this), baseToken.balanceOf(msg.sender));
        rootedToken.transferFrom(msg.sender, address(this), rootedToken.totalSupply());
    }

    function claim(address to, uint256 contribution, uint8 round) public override
    {
        require (distributionComplete, "Not complete");
        claimCallAmount[to][round] = contribution;
    }

    function claimRefRewards(address to, uint256 refShare) public override
    {
        require (distributionComplete, "Not complete");
        claimRefBonusCallAmount[to] = refShare;
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