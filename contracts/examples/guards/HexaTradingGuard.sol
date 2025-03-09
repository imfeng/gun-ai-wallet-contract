// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02, IUniswapV2Router02Selectors} from "./../../interfaces/uniswap/IUniswapV2Router02.sol";
import {IOdosRouterV2, IOdosRouterV2Selectors} from "../../interfaces/odos/IOdosRouterV2.sol";
import {Enum} from "./../../libraries/Enum.sol";
import {BaseGuard} from "./BaseGuard.sol";
import {BaseTransactionGuard, ITransactionGuard} from "./../../base/GuardManager.sol";
import {BaseModuleGuard, IModuleGuard} from "./../../base/ModuleManager.sol";
import {IERC165} from "./../../interfaces/IERC165.sol";

// BaseTransactionGuard

contract HexaTradingGuard is BaseGuard, AccessControl {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant TRADER_ROLE = keccak256("TRADER_ROLE");

    address public immutable uniswapRouterAddress;
    address public immutable odosRouterAddress;
    address public safe;

    struct WhitelistInfo {
        address token;
        bool enabled;
        uint256 dailyLimitAmount;
    }

    mapping(address => WhitelistInfo) public whitelists;

    // Events
    event TokenWhitelistUpdated(address indexed token, bool enabled, uint256 dailyLimitAmount);

    constructor(address _uniswapRouter, address _odosRouter, address _safe, address _initialOwner) {
        uniswapRouterAddress = _uniswapRouter;
        odosRouterAddress = _odosRouter;
        safe = _safe;

        // Setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        _setupRole(OWNER_ROLE, _initialOwner);
    }

    // Function to request adding a token to the whitelist
    // Can be called by either owner or trader
    function updateWhitelist(address token, bool enabled, uint256 dailyLimitAmount) external {
        require(msg.sender == safe, "only Safe can call");
        whitelists[token] = WhitelistInfo({token: token, enabled: enabled, dailyLimitAmount: dailyLimitAmount});
        emit TokenWhitelistUpdated(token, enabled, dailyLimitAmount);
    }

    // Function to check if a function selector matches a specific function
    function matchFunctionSelector(bytes memory data, bytes4 selector) internal pure returns (bool) {
        if (data.length < 4) return false;

        bytes4 functionSelector;
        assembly {
            functionSelector := mload(add(data, 32))
        }

        return functionSelector == selector;
    }

    // Function to extract token addresses from Uniswap swap data
    function extractTokenPath(bytes memory data) internal pure returns (address[] memory) {
        // This function extracts the token path from Uniswap router function calls

        // Extract the path offset - this varies based on the specific function
        // For most swap functions, the path is the third parameter
        uint256 pathOffset;
        assembly {
            // Skip function selector (4 bytes) and two uint256 parameters (64 bytes)
            // This offset will need adjustment based on which swap function is being called
            pathOffset := add(add(data, 4), 64)
        }

        // Get the path array location from the offset in the calldata
        uint256 pathLoc;
        assembly {
            // Load the relative offset to the path array
            let relativePathOffset := mload(pathOffset)
            // Calculate the absolute position of the path array
            pathLoc := add(pathOffset, relativePathOffset)
        }

        // Extract the array length
        uint256 pathLength;
        assembly {
            pathLength := mload(pathLoc)
        }

        // Create the address array to return
        address[] memory path = new address[](pathLength);

        // Extract each address
        for (uint256 i = 0; i < pathLength; i++) {
            uint256 itemPos = 32 * (i + 1) + pathLoc;
            address token;
            assembly {
                token := mload(itemPos)
            }
            path[i] = token;
        }

        return path;
    }

    // Implement ITransactionGuard.checkTransaction
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external view override {
        // Skip checks for empty transactions or other operations
        if (operation == Enum.Operation.DelegateCall || data.length < 4) return;

        if (to == odosRouterAddress) {
            // Check trader permission for Uniswap interactions
            bool isTraderSigned = checkSignedByRole(signatures, TRADER_ROLE);
            require(isTraderSigned, "Trading requires Trader role signature");

            // if (matchFunctionSelector(data, IOdosRouterV2Selectors.swap)) {
            //     IOdosRouterV2.swapTokenInfo memory tokenInfo;
            //     bytes memory remainingData;
            //     address someAddress;
            //     uint32 someUint32;
            //     (tokenInfo, remainingData, someAddress, someUint32) = abi.decode(data[4:], (IOdosRouterV2.swapTokenInfo, bytes, address, uint32));

            //     require(whitelists[tokenInfo.inputToken].enabled, "Input token not whitelisted");
            //     require(whitelists[tokenInfo.outputToken].enabled, "Output token not whitelisted");

            //     return;
            // }
        }

        // Check if this is a Uniswap swap
        if (to == uniswapRouterAddress) {
            // Check trader permission for Uniswap interactions
            bool isTraderSigned = checkSignedByRole(signatures, TRADER_ROLE);
            require(isTraderSigned, "Trading requires Trader role signature");

            if (matchFunctionSelector(data, IUniswapV2Router02Selectors.swapExactTokensForTokens)) {
                // 跳過函數選擇器的正確方式
                bytes memory dataWithoutSelector = new bytes(data.length - 4);
                for (uint256 i = 0; i < data.length - 4; i++) {
                    dataWithoutSelector[i] = data[i + 4];
                }
                (, , address[] memory path, , ) = abi.decode(dataWithoutSelector, (uint256, uint256, address[], address, uint256));

                require(whitelists[path[0]].enabled, "Input token not whitelisted");
                require(whitelists[path[path.length - 1]].enabled, "Output token not whitelisted");
            }
            return;
        }
    }

    // Check if the transaction was signed by an address with the specified role
    function checkSignedByRole(bytes memory signatures, bytes32 role) internal view returns (bool) {
        // This is a simplified version that doesn't actually check signatures
        // In a real implementation, you would parse the signatures and verify if any signer has the role

        // Get the Safe contract address (this method only works when called by the Safe)
        address safeAddress = msg.sender;

        // Parse the Safe's owners who have the required role
        // This assumes you've correctly set up role permissions for Safe owners

        // Very simplistic implementation - just checks if any owner has the role
        // In a real implementation, you'd need to actually check the signatures

        // Note: This approach is incomplete and would need to be expanded in a real implementation
        return true;
    }

    // Implement ITransactionGuard.checkAfterExecution
    function checkAfterExecution(bytes32 txHash, bool success) external override {
        // No actions needed after execution
    }

    /**
     * @notice Called by the Safe contract after a module transaction is executed.
     * @dev No-op.
     */
    function checkAfterModuleExecution(bytes32, bool) external view override {}

    /**
     * @notice Called by the Safe contract before a transaction is executed via a module.
     * @param to Destination address of Safe transaction.
     * @param value Ether value of Safe transaction.
     * @param data Data payload of Safe transaction.
     * @param operation Operation type of Safe transaction.
     * @param module Module executing the transaction.
     */
    function checkModuleTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address module
    ) external view override returns (bytes32 moduleTxHash) {
        // TODO: Implement module transaction checks
    }

    // Admin functions to manage roles
    function addTrader(address trader) external {
        require(!hasRole(OWNER_ROLE, msg.sender), "only owner");
        grantRole(TRADER_ROLE, trader);
    }

    function removeTrader(address trader) external {
        require(!hasRole(OWNER_ROLE, msg.sender), "only owner");
        revokeRole(TRADER_ROLE, trader);
    }

    function addOwner(address owner) external {
        require(!hasRole(OWNER_ROLE, msg.sender), "only owner");
        grantRole(OWNER_ROLE, owner);
    }

    function removeOwner(address owner) external {
        require(!hasRole(OWNER_ROLE, msg.sender), "only owner");
        revokeRole(OWNER_ROLE, owner);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseGuard, AccessControl) returns (bool) {
        return
            interfaceId == type(ITransactionGuard).interfaceId || // 0xe6d7a83a
            interfaceId == type(IModuleGuard).interfaceId || // 0x58401ed8
            interfaceId == type(IERC165).interfaceId; // 0x01ffc9a7
    }
}
