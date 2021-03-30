// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

import "./IMarketDistribution.sol";
import "./IMarketGeneration.sol";
import "./Owned.sol";
import "./RootedToken.sol";
import "./RootedTransferGate.sol";
import "./TokensRecoverable.sol";
import "./SafeMath.sol";
import "./EliteToken.sol";
import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IWrappedERC20.sol";
import "./SafeERC20.sol";

/*
Introducing the Market Generation Event:
TLDR: we create the market with all raised funds,
then use the same funds to buy from the market
and distribute to contributers. ERC31337 lets
anyone use the same ETH multiple times under 
some conditions.

Allows full and permanent liquidity locking of
all raised funds AND no commitment to LPs. Using
ERC-31337 we get ALL the raised funds back from 
liquidity if we lock all the raised token with
all the supply of the new token.
- Raise with any token
- All raised funds get locked forever
- users choose a buy group when they contribute
- (r1 75% to liq / 20% buy) (r2 50% liq / 50% % buy)
- (r1 75% to liq / 20% buy) (r2 50% liq / 50% % buy)
- multiple group buys before the market opens
- perma lock more into liquidity for earlier groups


Phases:
    Initializing
        Call setupEliteRooted()
        Call setupBaseRooted() 
        Call completeSetup()
        
    Call distribute() to:
        Transfer all rootedToken to this contract
        Take all BaseToken + rootedToken and create a market
        Sweep the floor
        Buy rootedToken for the group
        Move liquidity from elite pool to create standard pool
        Distribute funds

    Complete
        Everyone can call claim() to receive their tokens (via the liquidity generation contract)
*/

contract MarketDistribution is TokensRecoverable, IMarketDistribution
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public override distributionComplete;

    IUniswapV2Router02 immutable uniswapV2Router;
    IUniswapV2Factory immutable uniswapV2Factory;
    RootedToken immutable rootedToken;
    IERC31337 immutable eliteToken;
    IERC20 immutable baseToken;
    address immutable devAddress;

    IUniswapV2Pair rootedEliteLP;
    IUniswapV2Pair rootedBaseLP;

    uint256 public totalBaseTokenCollected;
    mapping (uint8 => uint256) public totalRootedTokenBoughtPerRound;
    mapping (address => uint256) public claimTime; // address > time    
    mapping (address => uint256) public totalOwed;
    uint256 public totalBoughtForReferrals;
    IMarketGeneration marketGeneration;
    uint256 public recoveryDate = block.timestamp + 2592000; // 1 Month
    
    uint16 constant public devCutPercent = 900; // 9%
    uint16 constant public preBuyForReferralsPercent = 200; // 2%
    uint16 constant public preBuyForMarketManipulationPercent = 900; // 9%
    uint256 public override vestingPeriodStartTime;
    uint256 public override vestingEnd; // 7 days
    uint256 public vestingDuration = 600000 seconds;
    uint256 rootedBottom;

    constructor(RootedToken _rootedToken, IUniswapV2Router02 _uniswapV2Router, IERC31337 _eliteToken, address _devAddress)
    {
        require (address(_rootedToken) != address(0));

        rootedToken = _rootedToken;
        uniswapV2Router = _uniswapV2Router;
        eliteToken = _eliteToken;

        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Router.factory());
        baseToken = _eliteToken.wrappedToken();
        devAddress = _devAddress;
    }

    function setupEliteRooted() public
    {
        rootedEliteLP = IUniswapV2Pair(uniswapV2Factory.getPair(address(eliteToken), address(rootedToken)));
        if (address(rootedEliteLP) == address(0)) 
        {
            rootedEliteLP = IUniswapV2Pair(uniswapV2Factory.createPair(address(eliteToken), address(rootedToken)));
            require (address(rootedEliteLP) != address(0));
        }
    }

    function setupBaseRooted() public
    {
        rootedBaseLP = IUniswapV2Pair(uniswapV2Factory.getPair(address(baseToken), address(rootedToken)));
        if (address(rootedBaseLP) == address(0)) 
        {
            rootedBaseLP = IUniswapV2Pair(uniswapV2Factory.createPair(address(baseToken), address(rootedToken)));
            require (address(rootedBaseLP) != address(0));
        }
    }

    function completeSetup() public ownerOnly()
    {       
        eliteToken.approve(address(uniswapV2Router), uint256(-1));
        rootedToken.approve(address(uniswapV2Router), uint256(-1));
        baseToken.approve(address(uniswapV2Router), uint256(-1));
        baseToken.approve(address(eliteToken), uint256(-1));
        rootedBaseLP.approve(address(uniswapV2Router), uint256(-1));
        rootedEliteLP.approve(address(uniswapV2Router), uint256(-1));
    }

    function distribute() public override
    {
        require (!distributionComplete, "Distribution complete");

        marketGeneration = IMarketGeneration(msg.sender);
        uint256 totalContributions = baseToken.balanceOf(address(marketGeneration));

        require (totalContributions > 0, "Nothing to distribute");

        vestingPeriodStartTime = block.timestamp;
        vestingEnd = block.timestamp + vestingDuration;
        distributionComplete = true;
        totalBaseTokenCollected = totalContributions;
        baseToken.safeTransferFrom(msg.sender, address(this), totalBaseTokenCollected);
        
        rootedToken.mint(totalBaseTokenCollected);

        RootedTransferGate gate = RootedTransferGate(address(rootedToken.transferGate()));
        gate.setUnrestricted(true);

        createRootedEliteLiquidity();

        eliteToken.sweepFloor(address(this));
        eliteToken.depositTokens(baseToken.balanceOf(address(this)));  

        uint256 devCut = totalBaseTokenCollected * devCutPercent / 10000;        
        buyTheBottom(devCut);     

        preBuyForMarketManipulation();
        preBuyForReferrals();
        preBuyForGroups();

        eliteToken.transfer(devAddress, eliteToken.balanceOf(address(this))); // pump fund, send direct to bobber in future

        sellTheTop();
        createRootedBaseLiquidity();

        gate.setUnrestricted(false);
    }
    
    function buyTheBottom(uint256 devCut) private
    {
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(devCut, 0, eliteRootedPath(), address(this), block.timestamp);
        rootedBottom = amounts[1];
    }

    function sellTheTop() private
    {
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(rootedBottom, 0, rootedElitePath(), address(this), block.timestamp);
        uint256 eliteAmount = amounts[1];
        eliteToken.withdrawTokens(eliteAmount);
        baseToken.safeTransfer(devAddress, eliteAmount);
    }
    
    function createRootedEliteLiquidity() private
    {
        // Create Rooted/Elite LP 
        eliteToken.depositTokens(baseToken.balanceOf(address(this)));
        uniswapV2Router.addLiquidity(address(eliteToken), address(rootedToken), eliteToken.balanceOf(address(this)), rootedToken.totalSupply(), 0, 0, address(this), block.timestamp);
    }

    function preBuyForMarketManipulation() private 
    {
        uint256 amount = totalBaseTokenCollected * preBuyForMarketManipulationPercent / 10000;        
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(amount, 0, eliteRootedPath(), address(this), block.timestamp);
        uint256 rootedAmout = amounts[1];
        rootedToken.transfer(devAddress, rootedAmout); // send to Bobber
    }
    
    function preBuyForReferrals() private 
    {
        uint256 amount = totalBaseTokenCollected * preBuyForReferralsPercent / 10000; // buy at best possible price to feed the shillage.
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(amount, 0, eliteRootedPath(), address(this), block.timestamp);
        totalBoughtForReferrals = amounts[1];
    }

    function preBuyForGroups() private 
    {          
        for (uint8 round = 1; round <= marketGeneration.buyRoundsCount(); round++)
        {
            uint256 totalRound = marketGeneration.totalContributionPerRound(round);
            uint256 buyPercent = round * 3000; // 10000 = 100%
            uint256 roundBuy = totalRound * buyPercent / 10000;

            if (roundBuy > 0)
            {                
                uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(roundBuy, 0, eliteRootedPath(), address(this), block.timestamp);
                totalRootedTokenBoughtPerRound[round] = amounts[1];
            }            
        }
    }

    function createRootedBaseLiquidity() private
    {
        uint256 elitePerLpToken = eliteToken.balanceOf(address(rootedEliteLP)).mul(1e18).div(rootedEliteLP.totalSupply());
        uint256 lpAmountToRemove = baseToken.balanceOf(address(eliteToken)).mul(1e18).div(elitePerLpToken);
       
        (uint256 eliteAmount, uint256 rootedAmount) = uniswapV2Router.removeLiquidity(address(eliteToken), address(rootedToken), lpAmountToRemove, 0, 0, address(this), block.timestamp);
        
        uint256 baseInElite = baseToken.balanceOf(address(eliteToken));
        uint256 baseAmount = eliteAmount > baseInElite ? baseInElite : eliteAmount;
        
        eliteToken.withdrawTokens(baseInElite);
        uniswapV2Router.addLiquidity(address(baseToken), address(rootedToken), baseAmount, rootedAmount, 0, 0, address(this), block.timestamp);
        rootedBaseLP.transfer(devAddress, rootedBaseLP.balanceOf(address(this)));
        rootedEliteLP.transfer(devAddress, rootedEliteLP.balanceOf(address(this)));
    }

    function eliteRootedPath() private view returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = address(eliteToken);
        path[1] = address(rootedToken);
        return path;
    }

    function rootedElitePath() private view returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = address(rootedToken);
        path[1] = address(eliteToken);
        return path;
    }
    
    function getTotalOwed(address account) private view returns (uint256)
    {
        uint256 total;

        for (uint8 round = 1; round <= marketGeneration.buyRoundsCount(); round++)
        {           
            uint256 contribution = marketGeneration.contributionPerRound(account, round);

            if (contribution > 0)
            {
                uint256 totalRound = marketGeneration.totalContributionPerRound(round);
                uint256 share = contribution.mul(totalRootedTokenBoughtPerRound[round]) / totalRound;
                total = total + share;
            }           
        }

        return total;
    }

    function claim(address account) public override 
    {
        require (msg.sender == address(marketGeneration), "Unauthorized");

        if (totalOwed[account] == 0)
        {
            totalOwed[account] = getTotalOwed(account);
        }

        uint256 share = totalOwed[account];  
        uint256 endTime = vestingEnd > block.timestamp ? block.timestamp : vestingEnd;

        require (claimTime[account] <= endTime, "Already claimed");

        uint256 claimStartTime = claimTime[account] == 0 ? vestingPeriodStartTime : claimTime[account];
        share = (endTime.sub(claimStartTime)).mul(share).div(vestingDuration);        
        claimTime[account] = block.timestamp;
        rootedToken.transfer(account, share);
    }

    function claimReferralRewards(address account, uint256 referralShare) public override 
    {
        require (msg.sender == address(marketGeneration), "Unauthorized");

        uint256 share = referralShare.mul(totalBoughtForReferrals).div(marketGeneration.totalReferralPoints());
        rootedToken.transfer(account, share);
    }

    function canRecoverTokens(IERC20 token) internal override view returns (bool) 
    { 
        return block.timestamp > recoveryDate || token != rootedToken;
    }
}