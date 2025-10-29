// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {StakingNFT} from "../src/Stake.sol";
import {MockERC20Permit} from "../src/mockBEP20.sol";

contract StakingNFTTest is Test {
    StakingNFT public staking;
    MockERC20Permit public token;

    address alice = address(0x1);
    address bob = address(0x2);
    address referrer = address(0x3);

    function setUp() public {
        // Deploy token and mint to alice and bob
        token = new MockERC20Permit();
        token.mint(alice, 1_000 ether); // here 1_000 ether = 1_000 * 1e18
        token.mint(bob, 1_000 ether);

        // Deploy staking contract
        staking = new StakingNFT("StakeNFT", "SNFT", address(token));

        // Fund staking contract with tokens to pay rewards
        token.mint(address(staking), 10_000 ether);
    }

    function testStake() public {
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        uint256 stakeId = staking.stake(100 ether, address(0));
        assertEq(staking.ownerOf(stakeId), alice);
        (,, uint256 amountStaked,,) = staking.stakeIdToStakeData(stakeId);
        assertEq(amountStaked, 100 ether);
        vm.stopPrank();
    }

    function testStakeWithReferrer() public {
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        uint256 stakeId = staking.stake(100 ether, referrer);
        assertEq(staking.ownerOf(stakeId), alice);
        (, address stakeReferrer, uint256 amountStaked,,) = staking.stakeIdToStakeData(stakeId);
        // amountStaked should be 100 ether - 0.5% referral (50/10000)
        uint256 expectedAmount = 100 ether - ((100 ether * 50) / 10000);
        assertEq(amountStaked, expectedAmount);
        vm.stopPrank();

        // Check referrer got paid immediately
        assertEq(token.balanceOf(referrer), (100 ether * 50) / 10000);
    }

    function testClaim() public {
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        uint256 stakeId = staking.stake(100 ether, address(0));

        // Advance time by 1 day + 1 second to pass claim interval
        vm.warp(block.timestamp + 1 days + 1);

        uint256 balanceBefore = token.balanceOf(alice);
        staking.claim(stakeId, alice);
        uint256 balanceAfter = token.balanceOf(alice);

        // Reward = principal * DAILY(100) / DEN(10000) * daysPassed(1)
        uint256 expectedReward = (100 ether * 100) / 10000;
        assertEq(balanceAfter - balanceBefore, expectedReward);
        vm.stopPrank();
    }

    function testUnstake() public {
        vm.startPrank(alice);
        token.approve(address(staking), 100 ether);
        uint256 stakeId = staking.stake(100 ether, address(0));

        // Advance time by 1 day + 1 second to accrue rewards
        vm.warp(block.timestamp + 1 days + 1);

        uint256 aliceBalBefore = token.balanceOf(alice);
        staking.unstake(stakeId, alice);
        uint256 aliceBalAfter = token.balanceOf(alice);

        // Principal + reward
        uint256 reward = (100 ether * 100) / 10000;
        uint256 expectedTotal = 100 ether + reward;
        assertEq(aliceBalAfter - aliceBalBefore, expectedTotal);

        // Stake NFT should be burned, ownerOf reverts
        vm.expectRevert();
        staking.ownerOf(stakeId);
        vm.stopPrank();
    }

    function testStakeWithPermit() public {
        vm.startPrank(alice);

        uint256 amount = 100 ether;
        uint256 nonce = token.nonces(alice);
        uint256 deadline = block.timestamp + 1 days;

        // Prepare EIP712 permit digest
        bytes32 DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                alice,
                address(staking),
                amount,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, digest);

        staking.stakeWithPermit(amount, address(0), deadline, v, r, s);
        vm.stopPrank();
    }
}
