// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

import "./ERC31337.sol";
import "./IEliteToken.sol";
import "./IERC20.sol";

contract EliteToken is ERC31337, IEliteToken
{
    using Address for address;
    using SafeMath for uint256;
    
    mapping (address => bool) public freeParticipantControllers;
    mapping (address => bool) public freeParticipant;
    uint16 burnRate;   

    constructor (IERC20 _wrappedToken) ERC31337(_wrappedToken, "RootKit [Wrapped ETH]", "RK:ETH")
    {
    }    

    function setFreeParticipantController(address freeParticipantController, bool allow) public ownerOnly()
    {
        freeParticipantControllers[freeParticipantController] = allow;
    }

    function setFreeParticipant(address participant, bool free) public
    {
        require (msg.sender == owner || freeParticipantControllers[msg.sender], "Not an Owner or Free Participant");
        freeParticipant[participant] = free;
    }

    function setBurnRate(uint16 _burnRate) public ownerOnly() // 10000 = 100%
    {
        require (_burnRate <= 10000, "> 100%");
       
        burnRate = _burnRate;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override 
    {
        require(sender != address(0), "ERC31337: transfer from the zero address");
        require(recipient != address(0), "ERC31337: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);
        uint256 remaining = amount;

        if (burnRate > 0)
        {
            uint256 burn = amount * burnRate / 10000;
            amount = remaining = remaining.sub(burn, "Burn too much");
            _burn(sender, burn);
        }
        
        _balanceOf[sender] = _balanceOf[sender].sub(amount, "ERC31337: transfer amount exceeds balance");
        _balanceOf[recipient] = _balanceOf[recipient].add(remaining);
        
        emit Transfer(sender, recipient, remaining);
    }
}