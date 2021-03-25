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

    mapping (address => mapping (uint8 => uint256)) public contribution; // address > round > amount 
    mapping (uint8 => uint256) public override roundTotals; // total contributed to each buy round
    mapping (address => uint256) public override refPoints; // address > amount
    uint256 public override totalRefPoints;
    address public devAddr;

    bool public isActive;

    IERC20 immutable baseToken;
    RootedToken immutable rootedToken;
    IMarketDistribution public marketDistribution;
    uint256 refundsAllowedUntil;
    uint256 totalRaised;
    uint256 hardCap;
    uint8 constant public override buyRoundsCount = 3;

    constructor (RootedToken _rootedToken, IERC20 _baseToken, uint256 _hardCap, address _devAddr)
    {
        rootedToken = _rootedToken;
        baseToken = _baseToken;
        hardCap = _hardCap;
        devAddr = _devAddr;
    }

    modifier active()
    {
        require (isActive, "Distribution not active");
        _;
    }

    function activate(IMarketDistribution _marketDistribution) public ownerOnly()
    {
        require (!isActive && block.timestamp >= refundsAllowedUntil, "Already activated");        
        require (rootedToken.balanceOf(address(this)) == rootedToken.totalSupply(), "Missing supply");
        require (address(_marketDistribution) != address(0));
        marketDistribution = _marketDistribution;
        isActive = true;
    }

    function setMarketDistribution(IMarketDistribution _marketDistribution) public ownerOnly() active()
    {
        require (address(_marketDistribution) != address(0));
        if (_marketDistribution == marketDistribution) { return; }
        marketDistribution = _marketDistribution;

        // Give everyone 1 day to claim refunds if they don't approve of the new distributor
        refundsAllowedUntil = block.timestamp + 86400;
    }

    function complete() public ownerOnly() active()
    {
        require (block.timestamp >= refundsAllowedUntil, "Refund period is still active");
        isActive = false;
        if (baseToken.balanceOf(address(this)) == 0) { return; }

        rootedToken.approve(address(marketDistribution), uint256(-1));
        baseToken.approve(address(marketDistribution), uint256(-1));

        marketDistribution.distribute();
    }

    function allowRefunds() public ownerOnly() active()
    {
        isActive = false;
        refundsAllowedUntil = uint256(-1);
    }

    function claim(uint8 round) public 
    {
        uint256 amount = contribution[msg.sender][round];

        require (amount > 0, "Nothing to claim");
        
        if (refundsAllowedUntil > block.timestamp) 
        {
            baseToken.safeTransfer(msg.sender, amount);
            contribution[msg.sender][round] = 0;
        }
        else 
        {
            marketDistribution.claim(msg.sender, amount, round);
        }
    }

    function claimAll() public
    {
        for (uint8 round = 1; round <= buyRoundsCount; round++)
        {
            uint256 amount = contribution[msg.sender][round];

            if (amount > 0)
            {            
                if (refundsAllowedUntil > block.timestamp) 
                {
                    contribution[msg.sender][round] = 0;
                    baseToken.safeTransfer(msg.sender, amount);
                }
                else 
                {
                    marketDistribution.claim(msg.sender, amount, round);
                }
            }            
        }        
    }

    function claimRefBonus() public
    {
        require (refPoints[msg.sender] > 0, "No bonus to claim");
        uint256 refShare = refPoints[msg.sender];
        refPoints[msg.sender] = 0;
        marketDistribution.claimRefRewards(msg.sender, refShare);
    }

    function contribute(uint256 amount, uint8 round, address ref) public active() 
    {
        require (round > 0 && round <= buyRoundsCount, "Round is 1 to 3");
        require (totalRaised <= hardCap, "Hardcap reached");

        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        if (ref == address(0)) 
        {
            refPoints[devAddr] = refPoints[devAddr] + amount;
            totalRefPoints = totalRefPoints + amount;
        }
        else 
        {
            refPoints[msg.sender] = refPoints[msg.sender] + amount;
            refPoints[ref] = refPoints[ref] + amount;
            totalRefPoints = totalRefPoints + amount + amount;
        }

        totalRaised = totalRaised + amount;

        uint256 oldContribution = contribution[msg.sender][round];
        uint256 newContribution = oldContribution + amount;
        contribution[msg.sender][round] = newContribution;

        uint256 oldTotal = roundTotals[round];
        uint256 newTotal = oldTotal + amount;

        roundTotals[round] = newTotal;
    }
}