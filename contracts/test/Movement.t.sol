// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Reputation should measure conviction, not conformity.
///
///         The market has no external referee — "right" means "agreed with the eventual
///         majority". Paying for that alone rewards herding and, since reputation weights
///         future votes, compounds it. Movement fixes it without needing any facts:
///         it asks whether consensus travelled toward you *after* you committed.
contract MovementTest is Test {
    bytes32 constant H = keccak256("x");
    NotchToken token;
    Reputation rep;
    NotchMarket market;

    address researcher = makeAddr("researcher");
    address early = makeAddr("early");
    address late_ = makeAddr("late");
    address crowd = makeAddr("crowd");
    address opposition = makeAddr("opposition");
    uint256 dn;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.initializeMarket(address(market));
        dn = market.createDatanet("d", "d", 1 ether, 3 days, 0);

        address[5] memory who = [researcher, early, late_, crowd, opposition];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 150_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    function _settle(uint256 id) internal {
        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);
    }

    /// Two reviewers stake the same amount on the same winning side. One went in while
    /// that side was losing; the other joined once it was already ahead. They must not
    /// be paid the same.
    function test_earlyConvictionOutEarnsLateHerding() public {
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, 1 ether);

        // NO leads first, so backing YES here is contrarian.
        vm.prank(opposition);
        market.review(id, false, 400 ether);
        vm.prank(early);
        market.review(id, true, 100 ether); // enters with YES well behind

        // The crowd arrives and swings it to YES.
        vm.prank(crowd);
        market.review(id, true, 600 ether);

        // Now YES is clearly ahead — this one is joining a queue.
        vm.prank(late_);
        market.review(id, true, 100 ether);

        _settle(id);
        assertTrue(market.getArtifact(id).outcomeYes, "YES should win");

        vm.prank(early);
        market.claim(id);
        vm.prank(late_);
        market.claim(id);

        uint256 earlyReps = rep.repOf(early);
        uint256 lateReps = rep.repOf(late_);
        emit log_named_uint("early (staked while behind)", earlyReps);
        emit log_named_uint("late  (staked while ahead)", lateReps);

        assertGt(earlyReps, lateReps, "conviction must out-earn conformity");
    }

    /// Joining a side that is already at the top of its range leaves no room for
    /// consensus to move toward you, so it mints nothing.
    function test_joiningADecidedMarketEarnsNothing() public {
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, 1 ether);

        vm.prank(crowd);
        market.review(id, true, 10_000 ether);
        vm.prank(opposition);
        market.review(id, false, 100 ether); // keeps the contest factor non-zero
        vm.prank(late_);
        market.review(id, true, 500 ether); // piles onto a settled leader

        _settle(id);
        vm.prank(late_);
        market.claim(id);

        assertEq(rep.repOf(late_), 0, "no movement, no reputation");
    }

    /// The farm guard still holds: with nobody opposing, the contest factor is zero and
    /// movement cannot rescue it.
    function test_uncontestedStillEarnsNothing() public {
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, 1 ether);
        vm.prank(crowd);
        market.review(id, true, 50_000 ether);

        _settle(id);
        vm.prank(crowd);
        market.claim(id);

        assertEq(rep.repOf(crowd), 0, "unopposed markets mint nothing");
    }

    /// Being on the winning side while consensus drifted *away* from you is not
    /// judgment, and pays accordingly.
    function test_marketMovingAwayPaysNothing() public {
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, 1 ether);

        // YES starts dominant; this reviewer enters near the top.
        vm.prank(crowd);
        market.review(id, true, 1_000 ether);
        vm.prank(late_);
        market.review(id, true, 100 ether);
        // Opposition closes the gap without overtaking.
        vm.prank(opposition);
        market.review(id, false, 900 ether);

        _settle(id);
        assertTrue(market.getArtifact(id).outcomeYes);

        vm.prank(late_);
        market.claim(id);
        assertEq(rep.repOf(late_), 0, "consensus moved away, nothing earned");
    }
}
