// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.0 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Token
 * @dev This contract is an ERC20 token contract that extends the OpenZeppelin ERC20 contract.
 */
contract ERC20Token is ERC20 {
    /**
     * @dev Constructor that sets the name and symbol of the token and mints an initial supply to the contract deployer.
     */
    constructor() ERC20("TestToken", "TT") {
        _mint(msg.sender, 1000000000000000);
    }

    /**
     * @dev Function to mint tokens to a specified address.
     * @param to The address to which the tokens will be minted.
     * @param amount The amount of tokens to be minted.
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
