//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ProxyRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenTransferProxy {
    using SafeERC20 for IERC20;

    ProxyRegistry public registry;

    constructor (ProxyRegistry registryAddr)
    {
        registry = registryAddr;
    }

    function transferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) public {
        require(registry.contracts(msg.sender));
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
