// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./examples/guards/HexaTradingGuard.sol";

/**
 * @title HexaTradingGuardFactory
 * @dev Factory contract for deploying new HexaTradingGuard instances
 */
contract HexaTradingGuardFactory {
    // Events
    event GuardCreated(address indexed guardAddress, address indexed safe, address indexed owner);

    /**
     * @notice Creates a new HexaTradingGuard instance
     * @param _uniswapRouter Address of the Uniswap Router
     * @param _safe Address of the Safe contract
     * @param _initialOwner Address of the initial owner
     * @return The address of the newly created guard
     */
    function createGuard(address _uniswapRouter, address _odosRouter, address _safe, address _initialOwner) external returns (address) {
        // Deploy a new guard
        HexaTradingGuard newGuard = new HexaTradingGuard(_uniswapRouter, _odosRouter, _safe, _initialOwner);

        address guardAddress = address(newGuard);

        // Emit event
        emit GuardCreated(guardAddress, _safe, _initialOwner);

        return guardAddress;
    }
}
