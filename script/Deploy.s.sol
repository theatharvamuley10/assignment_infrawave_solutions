// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {MockBEP20Permit} from "../src/mockBEP20.sol";
import {StakingNFT} from "../src/Stake.sol";

contract Deploy is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy MockERC20Permit token
        MockBEP20Permit mockToken = new MockBEP20Permit();

        // Deploy StakingNFT with token address
        StakingNFT stakingNFT = new StakingNFT("Stake Contract For Infrawave", "SCI", address(mockToken));

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployed addresses
        console.log("MockERC20Permit deployed at:", address(mockToken));
        console.log("StakingNFT deployed at:", address(stakingNFT));
    }
}
