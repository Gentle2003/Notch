// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Appeals exist so that holding a false outcome costs more each round, while an
///         honest challenger pays once. These tests pin that asymmetry.
contract AppealsTest is Test {
    bytes32 constant H = keccak256("x");
    NotchToken token;
    Reputation rep;
    NotchMarket market;

    address researcher = makeAddr("researcher");
    address whale = makeAddr("whale");
    address challenger = makeAddr("challenger");
    address bystander = makeAddr("bystander");
    uint256 dn;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.initializeMarket(address(market));
        dn = market.createDatanet("d", "d", 1 ether, 3 days, 0);

        address[4] memory who = [researcher, whale, challenger, bystander];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 200_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    function _open() internal returns (uint256 id) {
        vm.prank(researcher);
        id = market.submitArtifact(dn, "t", "uri", H, 10 ether);
    }

    function _closeReview(uint256 id) internal {
        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
    }

    /// resolve() no longer settles anything by itself — it posts a provisional outcome
    /// and money stays locked until the challenge window has passed.
    function test_resolveIsProvisionalAndClaimsAreLocked() public {
        uint256 id = _open();
        vm.prank(whale);
        market.review(id, true, 100 ether);
        _closeReview(id);

        assertEq(uint8(market.getArtifact(id).status), uint8(NotchMarket.Status.Challengeable));

        vm.prank(whale);
        vm.expectRevert(bytes("not final"));
        market.claim(id);
    }

    /// Unchallenged, a provisional outcome finalises once the window elapses.
    function test_unchallengedOutcomeFinalises() public {
        uint256 id = _open();
        vm.prank(whale);
        market.review(id, true, 100 ether);
        _closeReview(id);

        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);

        assertEq(uint8(market.getArtifact(id).status), uint8(NotchMarket.Status.Final));
        vm.prank(whale);
        market.claim(id); // no longer reverts
    }

    /// The core case: a whale buys a wrong outcome in round 0, a challenger reopens it,
    /// and the market corrects. A single round of appeal is enough to undo capital.
    function test_challengeCanFlipAWrongOutcome() public {
        uint256 id = _open();

        // Whale overwhelms the honest reviewer.
        vm.prank(bystander);
        market.review(id, false, 100 ether);
        vm.prank(whale);
        market.review(id, true, 500 ether);

        _closeReview(id);
        assertTrue(market.getArtifact(id).outcomeYes, "capital wins round 0");

        // Challenger disputes; the bond is staked against the provisional outcome.
        uint256 bond = market.challengeBond(id);
        vm.prank(challenger);
        market.challenge(id);

        NotchMarket.Artifact memory a = market.getArtifact(id);
        assertEq(uint8(a.status), uint8(NotchMarket.Status.Reviewing), "review reopens");
        assertEq(a.round, 1);
        assertEq(a.noStake, 100 ether + bond, "bond backs the challenged side");

        _closeReview(id);
        assertFalse(market.getArtifact(id).outcomeYes, "the appeal corrected it");
    }

    /// Each round doubles the bond, so defending a false result compounds while the
    /// challenger pays once.
    function test_bondDoublesEachRound() public {
        uint256 id = _open();
        vm.prank(bystander);
        market.review(id, false, 100 ether);
        vm.prank(whale);
        market.review(id, true, 500 ether);
        _closeReview(id);

        uint256 round0 = market.challengeBond(id);
        vm.prank(challenger);
        market.challenge(id);
        _closeReview(id);

        uint256 round1 = market.challengeBond(id);
        assertEq(market.getArtifact(id).round, 1);
        // margin << round: the same margin costs twice as much to dispute again
        assertEq(round1, round0 * 2, "each round doubles the bond");
    }

    /// Appeals are finite. After MAX_ROUNDS the outcome stands, which is the honest
    /// limit of this design — enough capital still wins the last round.
    function test_appealsAreExhaustible() public {
        uint256 id = _open();
        vm.prank(bystander);
        market.review(id, false, 100 ether);
        vm.prank(whale);
        market.review(id, true, 200 ether);
        _closeReview(id);

        for (uint256 i; i < 3; i++) {
            vm.prank(challenger);
            market.challenge(id);
            _closeReview(id);
        }

        NotchMarket.Artifact memory a = market.getArtifact(id);
        assertEq(a.round, 3, "MAX_ROUNDS reached");
        assertEq(uint8(a.status), uint8(NotchMarket.Status.Final), "final without a window");

        vm.prank(challenger);
        vm.expectRevert(bytes("not challengeable"));
        market.challenge(id);
    }

    function test_cannotChallengeAfterWindow() public {
        uint256 id = _open();
        vm.prank(whale);
        market.review(id, true, 100 ether);
        _closeReview(id);

        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        vm.prank(challenger);
        vm.expectRevert(bytes("challenge window closed"));
        market.challenge(id);
    }

    /// The author cannot buy validation of their own work, by review or by appeal.
    function test_submitterCannotChallenge() public {
        uint256 id = _open();
        vm.prank(whale);
        market.review(id, false, 100 ether);
        _closeReview(id);

        vm.prank(researcher);
        vm.expectRevert(bytes("submitter cannot challenge"));
        market.challenge(id);
    }

    /// Solvency has to survive the extra capital appeals introduce.
    function test_escrowStillDrainsAfterAnAppeal() public {
        uint256 id = _open();
        vm.prank(bystander);
        market.review(id, false, 100 ether);
        vm.prank(whale);
        market.review(id, true, 500 ether);
        _closeReview(id);

        vm.prank(challenger);
        market.challenge(id);
        _closeReview(id);

        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);

        address[4] memory all = [researcher, whale, challenger, bystander];
        for (uint256 i; i < all.length; i++) {
            vm.prank(all[i]);
            try market.claim(id) {} catch {}
        }
        assertEq(token.balanceOf(address(market)), 0, "escrow must still drain to zero");
    }
}
