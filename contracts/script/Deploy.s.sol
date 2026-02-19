// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {MonolithFactory} from "../src/MonolithFactory.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

contract Deploy is Script {
    // ERC-4337 v0.7 EntryPoint (same address on all chains)
    address constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        vm.startBroadcast();

        MonolithFactory factory = new MonolithFactory(IEntryPoint(ENTRY_POINT));
        console.log("Factory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
