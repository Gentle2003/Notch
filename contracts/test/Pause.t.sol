// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice A pause must stop money going in without trapping money already in.
contract PauseTest is Test {
    bytes32 constant H = keccak256("x");
    NotchToken token;
    Reputation rep;
    NotchMarket market;
    address researcher = makeAddr("researcher");
    address reviewer = makeAddr("reviewer");
    uint256 dn;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.initializeMarket(address(market));
        dn = market.createDatanet("d", "d", 1 ether, 3 days, 0);
        address[2] memory who = [researcher, reviewer];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 50_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    function test_pauseStopsNewStakes() public {
        market.pause();

        vm.prank(researcher);
        vm.expectRevert();
        market.submitArtifact(dn, "t", "uri", H, 10 ether);
    }

    /// The important half: an in-flight artifact can still be settled and claimed while
    /// paused, so a pause never strands funds.
    function test_pauseNeverTrapsFundsAlreadyStaked() public {
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, 10 ether);
        vm.prank(reviewer);
        market.review(id, true, 50 ether);

        market.pause();

        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id); // still works
        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id); // still works

        uint256 before = token.balanceOf(reviewer);
        vm.prank(reviewer);
        market.claim(id); // still works
        assertGt(token.balanceOf(reviewer), before, "exit must stay open while paused");
    }

    function test_onlyOwnerCanPause() public {
        vm.prank(reviewer);
        vm.expectRevert();
        market.pause();
    }

    function test_unpauseRestoresStaking() public {
        market.pause();
        market.unpause();
        vm.prank(researcher);
        market.submitArtifact(dn, "t", "uri", H, 10 ether);
    }
}
