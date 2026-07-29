// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {TestnetFaucet} from "../src/TestnetFaucet.sol";

/// @notice The token must have no way to mint after deployment. The faucet gives away
///         only what it holds, so the worst case is that it empties.
contract FaucetTest is Test {
    NotchToken token;
    TestnetFaucet faucet;
    address user = makeAddr("user");

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        faucet = new TestnetFaucet(address(token), address(this));
        token.transfer(address(faucet), 5_000 ether);
    }

    function test_supplyIsFixed() public view {
        assertEq(token.totalSupply(), token.INITIAL_SUPPLY(), "supply must be minted once");
    }

    function test_dripRespectsCooldown() public {
        vm.prank(user);
        faucet.drip();
        assertEq(token.balanceOf(user), 1_000 ether);

        vm.prank(user);
        vm.expectRevert(bytes("faucet: cooldown"));
        faucet.drip();

        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        faucet.drip();
        assertEq(token.balanceOf(user), 2_000 ether);
    }

    /// The faucet cannot conjure tokens — draining it does not inflate supply.
    function test_faucetCannotExceedItsBalance() public {
        uint256 supplyBefore = token.totalSupply();
        for (uint256 i; i < 5; i++) {
            address who = address(uint160(0xBEEF + i));
            vm.prank(who);
            faucet.drip();
        }
        assertEq(token.balanceOf(address(faucet)), 0, "faucet emptied");
        assertEq(token.totalSupply(), supplyBefore, "supply unchanged");

        vm.prank(makeAddr("latecomer"));
        vm.expectRevert(bytes("faucet: empty"));
        faucet.drip();
    }
}
