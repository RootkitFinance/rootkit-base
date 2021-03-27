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
    mapping (address => bool) public freeParticipants; // Free Participants are exempt from burn fee

    mapping (address => bool) public burnRateManagerControllers;
    mapping (address => bool) public burnRateManagers; // Burn Rate Managers set burn rate
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
        require (msg.sender == owner || freeParticipantControllers[msg.sender], "Not an Owner or Free Participant Controller");
        freeParticipants[participant] = free;
    }

    function setBurnRateManagerController(address burnRateManagerController, bool allow) public ownerOnly()
    {
        burnRateManagerControllers[burnRateManagerController] = allow;
    }

    function setBurnRateManager(address burnRateManager, bool free) public
    {
        require (msg.sender == owner || burnRateManagerControllers[msg.sender], "Not an Owner or Burn Rate Manager Controller");
        burnRateManagers[burnRateManager] = free;
    }

    function setBurnRate(uint16 _burnRate) public ownerOnly() // 10000 = 100%
    {
        require (msg.sender == owner || burnRateManagers[msg.sender], "Not an Owner or Burn Rate Manager");
        require (_burnRate <= 10000, "But rate must be less or equal to 100%");
       
        burnRate = _burnRate;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override 
    {
        require(sender != address(0), "EliteToken: transfer from the zero address");
        require(recipient != address(0), "EliteToken: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);
        uint256 remaining = amount;

        if (!freeParticipants[sender] && !freeParticipants[recipient] && burnRate > 0)
        {
            uint256 burn = amount * burnRate / 10000;
            amount = remaining = remaining.sub(burn, "Burn too much");
            _burn(sender, burn);
        }
        
        _balanceOf[sender] = _balanceOf[sender].sub(amount, "EliteToken: transfer amount exceeds balance");
        _balanceOf[recipient] = _balanceOf[recipient].add(remaining);
        
        emit Transfer(sender, recipient, remaining);
    }
}