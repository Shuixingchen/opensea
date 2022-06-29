//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./common/ArrayUtils.sol";

contract Test {
    constructor() {
        uint chainID;
        assembly{
            chainID:=chainid()
        }
        console.log(chainID);
    }

}
