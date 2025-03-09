// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;
pragma abicoder v2;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOdosRouterV2 {
    struct swapTokenInfo {
        address inputToken;
        uint256 inputAmount;
        address inputReceiver;
        address outputToken;
        uint256 outputQuote;
        uint256 outputMin;
        address outputReceiver;
    }

    function swap(
        swapTokenInfo memory tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable returns (uint256 amountOut);
}

/**
 * @title TermMax OdosAdapterV2Adapter
 * @author Term Structure Labs
 */
contract OdosV2Adapter {
    IOdosRouterV2 public immutable router;

    constructor(address router_) {
        router = IOdosRouterV2(router_);
    }

    function _swap(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        bytes memory swapData
    ) internal virtual returns (uint256 tokenOutAmt) {
        IERC20(tokenIn).approve(address(router), amountIn);

        (IOdosRouterV2.swapTokenInfo memory tokenInfo, bytes memory pathDefinition, address executor, uint32 referralCode) = abi.decode(
            swapData,
            (IOdosRouterV2.swapTokenInfo, bytes, address, uint32)
        );

        require(tokenInfo.outputToken == address(tokenOut), "INVALID_OUTPUT_TOKEN");
        /**
         * Note: Scaling Input/Output amount
         */
        tokenInfo.outputQuote = (tokenInfo.outputQuote * amountIn) / tokenInfo.inputAmount;
        tokenInfo.outputMin = (tokenInfo.outputMin * amountIn) / tokenInfo.inputAmount;
        tokenInfo.inputAmount = amountIn;
        tokenInfo.outputReceiver = address(this);

        tokenOutAmt = router.swap(tokenInfo, pathDefinition, executor, referralCode);
    }
}
