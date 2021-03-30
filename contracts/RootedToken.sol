// SPDX-License-Identifier: P-P-P-PONZO!!!
pragma solidity ^0.7.4;

/* ROOTKIT: The Age of Forks
Intended use:
- Raise any token using the MarketGeneration
and MarketDistribution contract
- combine with an ERC-31337 version of the 
raised token.


A Rooted Token is a token that gains in value
against whatever token it is paired with. In
some ways Rootkit.finance is just Rooted ETH. 
Its time to ROOT EVERYTHING ON EVERY CHAIN!!
*/

import "./GatedERC20.sol";

contract RootedToken is GatedERC20("RootKit", "ROOT")
{
    address public minter;

    function setMinter(address _minter) public ownerOnly()
    {
        minter = _minter;
    }

    function mint(uint256 amount) public
    {
        require(msg.sender == minter, "Not a minter");
        require(this.totalSupply() == 0, "Already minted");
        _mint(msg.sender, amount);
    }
}