//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../common/TokenRecipient.sol";
import "./ProxyRegistry.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract AuthenticatedProxy is TokenRecipient {
    using Address for address;

    address public user;

    ProxyRegistry public registry;

    bool public revoked;

    enum HowToCall {
        Call,
        DelegateCall
    }

    event Revoked(bool revoked);

    constructor(address addrUser, ProxyRegistry addrRegistry) {
        user = addrUser;
        registry = addrRegistry;
    }

    function setRevoke(bool revoke) public {
        require(msg.sender == user);
        revoked = revoke;
        emit Revoked(revoke);
    }

    function proxy(
        address dest,
        HowToCall howToCall,
        bytes memory calldatas
    ) public returns (bool result) {
        require(
            msg.sender == user || (!revoked && registry.contracts(msg.sender))
        );
        if (howToCall == HowToCall.Call) {
            dest.functionCall(calldatas);
        } else if (howToCall == HowToCall.DelegateCall) {
            dest.functionDelegateCall(calldatas);
        }
        return true;
    }
}
