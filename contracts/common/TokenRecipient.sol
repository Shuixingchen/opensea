//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenRecipient {
    using SafeERC20 for IERC20;

    event ReceivedEther(address indexed sender, uint amount);
    event ReceivedTokens(address indexed from, uint256 value, address indexed token, bytes extraData);

    function receiveApproval(address from, uint256 value, address token, bytes memory extraData) public {
        IERC20 t = IERC20(token);
        t.safeTransferFrom(from, address(this), value);
        emit ReceivedTokens(from, value, token, extraData);
    }

    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }
}