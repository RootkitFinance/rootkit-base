// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

/* ROOTKIT:
A transfer gate (GatedERC20) for use with RootKit tokens

It:
    Allows customization of tax and burn rates
    Allows transfer to/from approved Uniswap pools
    Disallows transfer to/from non-approved Uniswap pools
    Allows transfer to/from anywhere else
    Allows for free transfers if permission granted
    Allows for unrestricted transfers if permission granted
    Provides a safe and tax-free liquidity adding function
*/

import "./Owned.sol";
import "./IUniswapV2Factory.sol";
import "./IERC20.sol";
import "./IUniswapV2Pair.sol";
import "./EliteToken.sol";
import "./Address.sol";
import "./IUniswapV2Router02.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./TokensRecoverable.sol";
import "./ITransferGate.sol";
import "./FeeSplitter.sol";

contract RootedTransferGate is TokensRecoverable, ITransferGate
{   
    using Address for address;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    enum AddressState
    {
        Unknown,
        NotPool,
        DisallowedPool,
        AllowedPool
    }

    IUniswapV2Router02 immutable internal uniswapV2Router;
    IUniswapV2Factory immutable internal uniswapV2Factory;
    IERC31337 immutable internal rootedToken;

    mapping (address => AddressState) public addressStates;
    IERC20[] public allowedPoolTokens;
    
    bool public unrestricted;
    mapping (address => bool) public unrestrictedControllers;
    mapping (address => bool) public feeControllers;
    mapping (address => bool) public freeParticipantControllers;
    mapping (address => bool) public freeParticipant;

    mapping (address => uint256) public liquiditySupply;
    address public mustUpdate;

    FeeSplitter public feeSplitter;
    uint16 public feesRate; 
    uint16 public sellFeesRate;
    address public taxedPool;
   
    uint16 public dumpTaxStartRate; 
    uint256 public dumpTaxDurationInSeconds;
    uint256 public dumpTaxEndTimestamp;

    constructor(IERC31337 _rootedToken, IUniswapV2Router02 _uniswapV2Router)
    {
        rootedToken = _rootedToken;
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Router.factory());
    }

    function allowedPoolTokensCount() public view returns (uint256) { return allowedPoolTokens.length; }

    function setUnrestrictedController(address unrestrictedController, bool allow) public ownerOnly()
    {
        unrestrictedControllers[unrestrictedController] = allow;
    }

    function setFreeParticipantController(address freeParticipantController, bool allow) public ownerOnly()
    {
        freeParticipantControllers[freeParticipantController] = allow;
    }

    function setFeeControllers(address feeController, bool allow) public ownerOnly()
    {
        feeControllers[feeController] = allow;
    }

    function setFeeSplitter(FeeSplitter _feeSplitter) public ownerOnly()
    {
        feeSplitter = _feeSplitter;
    }

    function setFreeParticipant(address participant, bool free) public
    {
        require (msg.sender == owner || freeParticipantControllers[msg.sender], "Not an Owner or Free Participant");
        freeParticipant[participant] = free;
    }

    function setUnrestricted(bool _unrestricted) public
    {
        require (unrestrictedControllers[msg.sender], "Not an unrestricted controller");
        unrestricted = _unrestricted;
    }    

    function setTaxedPool(address _taxedPool) public ownerOnly()
    {
        if (taxedPool == address(0))
        {
            taxedPool = _taxedPool;
        }
    }

    function setDumpTax(uint16 startTaxRate, uint256 durationInSeconds) public
    {
        require (feeControllers[msg.sender] || msg.sender == owner, "Not an owner or fee controller");
        require (startTaxRate <= 1000, "Dump tax rate should be less than or equal to 10%");  // protecting everyone from Ponzo

        dumpTaxStartRate = startTaxRate;
        dumpTaxDurationInSeconds = durationInSeconds;
        dumpTaxEndTimestamp = block.timestamp + durationInSeconds;
    }

    function getDumpTax() public view returns (uint256)
    {
        if (block.timestamp >= dumpTaxEndTimestamp) 
        {
            return 0;
        }       
        
        return dumpTaxStartRate*(dumpTaxEndTimestamp - block.timestamp)*1e18/dumpTaxDurationInSeconds/1e18;
    }

    function setFees(uint16 _feesRate) public
    {
        require (feeControllers[msg.sender] || msg.sender == owner, "Not an owner or fee controller");
        require (_feesRate <= 1000, "> 10%"); // protecting everyone from Ponzo
        
        feesRate = _feesRate;
    }
    
    function setSellFees(uint16 _sellFeesRate) public
    {
        require (feeControllers[msg.sender] || msg.sender == owner, "Not an owner or fee controller");
        require (_sellFeesRate <= 2000, "> 20%"); // protecting everyone from Ponzo
        
        sellFeesRate = _sellFeesRate;
    }

    function allowPool(IERC20 token) public ownerOnly()
    {
        address pool = uniswapV2Factory.getPair(address(rootedToken), address(token));
        if (pool == address(0)) {
            pool = uniswapV2Factory.createPair(address(rootedToken), address(token));
        }
        AddressState state = addressStates[pool];
        require (state != AddressState.AllowedPool, "Already allowed");
        addressStates[pool] = AddressState.AllowedPool;
        allowedPoolTokens.push(token);
        liquiditySupply[pool] = IERC20(pool).totalSupply();
    }

    function handleTransfer(address, address from, address to, uint256 amount) public virtual override returns (address, uint256)
    {
        {
            address mustUpdateAddress = mustUpdate;
            if (mustUpdateAddress != address(0)) {
                mustUpdate = address(0);
                uint256 newSupply = IERC20(mustUpdateAddress).totalSupply();
                uint256 oldSupply = liquiditySupply[mustUpdateAddress];
                if (newSupply != oldSupply) {
                    liquiditySupply[mustUpdateAddress] = unrestricted ? newSupply : (newSupply > oldSupply ? newSupply : oldSupply);
                }
            }
        }
        {
            AddressState fromState = addressStates[from];
            AddressState toState = addressStates[to];
            if (fromState != AddressState.AllowedPool && toState != AddressState.AllowedPool) {
                if (fromState == AddressState.Unknown) { fromState = detectState(from); }
                if (toState == AddressState.Unknown) { toState = detectState(to); }
                require (unrestricted || (fromState != AddressState.DisallowedPool && toState != AddressState.DisallowedPool), "Pool not approved");
            }
            if (toState == AddressState.AllowedPool) {
                mustUpdate = to;
            }
            if (fromState == AddressState.AllowedPool) {
                if (unrestricted) {
                    liquiditySupply[from] = IERC20(from).totalSupply();
                }
                require (IERC20(from).totalSupply() >= liquiditySupply[from], "Cannot remove liquidity");            
            }
        }
        if (unrestricted || freeParticipant[from] || freeParticipant[to]) {
            return (address(feeSplitter), 0);
        }
        if (to == address(taxedPool)) {
            return (address(feeSplitter), amount * sellFeesRate / 10000 + amount * getDumpTax() / 10000);
        }
        // "amount" will never be > totalSupply which is capped at 10k, so these multiplications will never overflow      
        return (address(feeSplitter), amount * feesRate / 10000);
    }

    function setAddressState(address a, AddressState state) public ownerOnly()
    {
        addressStates[a] = state;
    }

    function detectState(address a) public returns (AddressState state) 
    {
        state = AddressState.NotPool;
        if (a.isContract()) {
            try this.throwAddressState(a)
            {
                assert(false);
            }
            catch Error(string memory result) {
                // if (bytes(result).length == 1) {
                //     state = AddressState.NotPool;
                // }
                if (bytes(result).length == 2) {
                    state = AddressState.DisallowedPool;
                }
            }
            catch {
            }
        }
        addressStates[a] = state;
        return state;
    }
    
    // Not intended for external consumption
    // Always throws
    // We want to call functions to probe for things, but don't want to open ourselves up to
    // possible state-changes
    // So we return a value by reverting with a message
    function throwAddressState(address a) external view
    {
        try IUniswapV2Pair(a).factory() returns (address factory)
        {
            if (factory == address(uniswapV2Factory)) {
                // these checks for token0/token1 are just for additional
                // certainty that we're interacting with a uniswap pair
                try IUniswapV2Pair(a).token0() returns (address token0)
                {
                    if (token0 == address(rootedToken)) {
                        revert("22");
                    }
                    try IUniswapV2Pair(a).token1() returns (address token1)
                    {
                        if (token1 == address(rootedToken)) {
                            revert("22");
                        }                        
                    }
                    catch { 
                    }                    
                }
                catch { 
                }
            }
        }
        catch {             
        }
        revert("1");
    }
}