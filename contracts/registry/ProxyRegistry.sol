//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./AuthenticatedProxy.sol";

contract ProxyRegistry is Ownable {
    uint256 public constant DELAY_PERIOD = 2 weeks;

    mapping(address => AuthenticatedProxy) public proxies;

    mapping(address => uint256) public pending;

    mapping(address => bool) public contracts;

    bool public initialAddressSet = false;

    constructor() {}

    function grantInitialAuthentication(address authAddress) public onlyOwner {
        require(!initialAddressSet);
        initialAddressSet = true;
        contracts[authAddress] = true;
    }

    function startGrantAuthentication(address addr) public onlyOwner {
        require(!contracts[addr] && pending[addr] == 0);
        pending[addr] = block.timestamp;
    }

    function endGrantAuthentication(address addr) public onlyOwner {
        require(
            !contracts[addr] &&
                pending[addr] != 0 &&
                ((pending[addr] + DELAY_PERIOD) < block.timestamp)
        );
        pending[addr] = 0;
        contracts[addr] = true;
    }

    function revokeAuthentication(address addr) public onlyOwner {
        contracts[addr] = false;
    }

    function registerProxy() public returns (AuthenticatedProxy proxy) {
        require(address(proxies[msg.sender]) == address(0));
        proxy = new AuthenticatedProxy(msg.sender, this);
        proxies[msg.sender] = proxy;
        return proxy;
    }
}
