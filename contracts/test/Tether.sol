// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

import "../ERC20.sol";

contract Tether is ERC20("Tether", "USDT") 
{ 
    constructor()
    {
        _mint(msg.sender, 100 ether);
        decimals = 6;
    }
}