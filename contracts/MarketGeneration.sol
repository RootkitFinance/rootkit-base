// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

import "./Owned.sol";
import "./RootedToken.sol";
import "./IMarketDistribution.sol";
import "./IMarketGeneration.sol";
import "./TokensRecoverable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

contract MarketGeneration is TokensRecoverable, IMarketGeneration
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    mapping (address => mapping (uint8 => uint256)) public override contributionPerRound; // address > round > amount 
    mapping (address => uint256) public override totalContribution; // address > amount 
    mapping (uint8 => uint256) public override totalContributionPerRound; // total contributed to each buy round
    mapping (address => uint256) public override referralPoints; // address > amount
    mapping (uint8 => bool) public disabledRounds;
    uint256 public override totalReferralPoints;
    address public devAddress;

    bool public isActive;

    IERC20 immutable baseToken;
    RootedToken immutable rootedToken;
    IMarketDistribution public marketDistribution;
    uint256 refundsAllowedUntil;
    uint256 totalRaised;
    uint8 constant public override buyRoundsCount = 3;

    constructor (RootedToken _rootedToken, IERC20 _baseToken, address _devAddress)
    {
        rootedToken = _rootedToken;
        baseToken = _baseToken;
        devAddress = _devAddress;
    }

    modifier active()
    {
        require (isActive, "Distribution not active");
        _;
    }

    function activate(IMarketDistribution _marketDistribution) public ownerOnly()
    {
        require (!isActive && block.timestamp >= refundsAllowedUntil, "Already activated");        
        require (address(_marketDistribution) != address(0));
        marketDistribution = _marketDistribution;
        isActive = true;
    }

    function setMarketDistribution(IMarketDistribution _marketDistribution) public ownerOnly() active()
    {
        require (address(_marketDistribution) != address(0), "Invalid market distribution");
        if (_marketDistribution == marketDistribution) { return; }
        marketDistribution = _marketDistribution;

        // Give everyone 1 day to claim refunds if they don't approve of the new distributor
        refundsAllowedUntil = block.timestamp + 86400;
    }

     function disableBuyRound(uint8 round, bool disabled) public ownerOnly() active()
    {
        require (round > 0 && round <= buyRoundsCount, "Round must be 1 to 3");
        disabledRounds[round] = disabled;
    }

    function complete() public ownerOnly() active()
    {
        require (block.timestamp >= refundsAllowedUntil, "Refund period is still active");
        isActive = false;
        if (baseToken.balanceOf(address(this)) == 0) { return; }

        rootedToken.approve(address(marketDistribution), uint256(-1));
        baseToken.safeApprove(address(marketDistribution), uint256(-1));

        marketDistribution.distribute();
    }

    function allowRefunds() public ownerOnly() active()
    {
        isActive = false;
        refundsAllowedUntil = uint256(-1);
    }

    function claim() public 
    {
        uint256 amount = totalContribution[msg.sender];

        require (amount > 0, "Nothing to claim");
        
        if (refundsAllowedUntil > block.timestamp) 
        {
            baseToken.safeTransfer(msg.sender, amount);
            totalContribution[msg.sender] = 0;
            contributionPerRound[msg.sender][1] = 0;
            contributionPerRound[msg.sender][2] = 0;
            contributionPerRound[msg.sender][3] = 0;
        }
        else 
        {
            marketDistribution.claim(msg.sender);
        }
    }

    function claimReferralBonus() public
    {
        require (referralPoints[msg.sender] > 0, "No bonus to claim");
        
        uint256 refShare = referralPoints[msg.sender];
        referralPoints[msg.sender] = 0;
        marketDistribution.claimReferralRewards(msg.sender, refShare);
    }

    function contribute(uint256 amount, uint8 round, address referral) public active() 
    {
        require (round > 0 && round <= buyRoundsCount, "Round must be 1 to 3");
        require (!disabledRounds[round], "Round is disabled");

        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        if (referral == address(0) || referral == msg.sender) 
        {
            uint256 oldReferralPoints = referralPoints[devAddress];
            uint256 newReferralPoints = oldReferralPoints + amount;
            referralPoints[devAddress] = newReferralPoints;
            totalReferralPoints = totalReferralPoints + amount;
        }
        else 
        {
            uint256 oldReferralPoints = referralPoints[msg.sender];
            uint256 newReferralPoints = oldReferralPoints + amount;
            referralPoints[msg.sender] = newReferralPoints;

            oldReferralPoints = referralPoints[referral];
            newReferralPoints = oldReferralPoints + amount;
            referralPoints[referral] = newReferralPoints;

            totalReferralPoints = totalReferralPoints + amount + amount;
        }

        totalRaised = totalRaised + amount;

        uint256 oldContribution = totalContribution[msg.sender];
        uint256 newContribution = oldContribution + amount;
        totalContribution[msg.sender] = newContribution;

        uint256 oldContributionPerRound = contributionPerRound[msg.sender][round];
        uint256 newContributionPerRound = oldContributionPerRound + amount;
        contributionPerRound[msg.sender][round] = newContributionPerRound;

        uint256 oldTotal = totalContributionPerRound[round];
        uint256 newTotal = oldTotal + amount;

        totalContributionPerRound[round] = newTotal;
    }
}