// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

contract NotchMarketTest is Test {

    /// Appeals: resolve() only posts a provisional outcome. Claims unlock once the
    /// challenge window has elapsed and someone finalises it.
    function _finalizeArtifact(uint256 id) internal {
        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);
    }
    bytes32 constant CONTENT_HASH = keccak256("analysis-v1");
    NotchToken token;
    Reputation rep;
    NotchMarket market;

    address owner = address(this);
    address researcher = makeAddr("researcher");
    address alice = makeAddr("alice"); // reviewer
    address bob = makeAddr("bob"); // reviewer
    address carol = makeAddr("carol"); // reviewer

    uint256 datanetId;

    function setUp() public {
        vm.warp(1_700_000_000); // realistic timestamp so faucet cooldown math holds
        token = new NotchToken();
        rep = new Reputation(owner);
        market = new NotchMarket(address(token), address(rep), owner);
        rep.initializeMarket(address(market));

        datanetId = market.createDatanet("RWA Research", "Analyses of tokenized RWAs", 10 ether, 3 days, 0);

        // Fund participants.
        address[4] memory who = [researcher, alice, bob, carol];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 10_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    function _submit(uint256 stake) internal returns (uint256 id) {
        vm.prank(researcher);
        id = market.submitArtifact(datanetId, "GOLD RWA thesis", "ipfs://cid", CONTENT_HASH, stake);
    }

    function test_submitStakeTooLow() public {
        vm.prank(researcher);
        vm.expectRevert(bytes("stake too low"));
        market.submitArtifact(datanetId, "t", "uri", CONTENT_HASH, 1 ether);
    }

    function test_submitterCannotReview() public {
        uint256 id = _submit(10 ether);
        vm.prank(researcher);
        vm.expectRevert(bytes("submitter cannot review"));
        market.review(id, true, 1 ether);
    }

    function test_yesWins_distributesLosingPool() public {
        uint256 id = _submit(10 ether); // submitter YES-weight 10

        vm.prank(alice);
        market.review(id, true, 20 ether); // YES 20
        vm.prank(bob);
        market.review(id, false, 12 ether); // NO 12 (loses)

        // consensus counts only reviewer stake (submitter excluded): yes=20 no=12 -> 20*10000/32 = 6250
        assertEq(market.consensusBps(id), 6250);

        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);

        NotchMarket.Artifact memory a = market.getArtifact(id);
        assertTrue(a.outcomeYes);

        // winWeight = 10 (submitter) + 20 (alice) = 30 ; losePool = 12
        // alice payout = 20 + 12*20/30 = 20 + 8 = 28
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(id);
        assertEq(token.balanceOf(alice) - aliceBefore, 28 ether);

        // submitter payout = 10 + 12*10/30 = 10 + 4 = 14
        uint256 rBefore = token.balanceOf(researcher);
        vm.prank(researcher);
        market.claim(id);
        assertEq(token.balanceOf(researcher) - rBefore, 14 ether);

        // bob (losing NO) gets nothing
        vm.prank(bob);
        vm.expectRevert(bytes("nothing to claim"));
        market.claim(id);

        // reps = repRate(5) * sqrt(stake) * contest * movement.
        // Both entered while the market was undecided (50%); it closed at 20/32 = 62.5%,
        // so movement = 0.125 for each. contest = 2*12/32 = 0.75.
        //   alice:      5 * sqrt(20)=4 * 0.75 * 0.125 = 1.87 -> 1
        //   researcher: 5 * sqrt(10)=3 * 0.75 * 0.125 = 1.40 -> 1
        // Small stakes and a small swing earn little, which is the intent.
        assertEq(rep.repOf(alice), 1);
        assertEq(rep.repOf(researcher), 1);
        assertEq(rep.repOf(bob), 0);

        // contract fully drained (no dust locked): 10+20+12 = 42 in, 28+14 = 42 out
        assertEq(token.balanceOf(address(market)), 0);
    }

    function test_noWins_slashesSubmitter() public {
        uint256 id = _submit(10 ether); // submitter YES-weight 10 (will be slashed)

        vm.prank(alice);
        market.review(id, false, 30 ether); // NO 30 (wins)
        vm.prank(bob);
        market.review(id, true, 5 ether); // YES 5 (loses)

        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);
        NotchMarket.Artifact memory a = market.getArtifact(id);
        assertFalse(a.outcomeYes);

        // winWeight = 30 (alice NO) ; losePool = yes(5) + submit(10) = 15
        // alice payout = 30 + 15 = 45
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        market.claim(id);
        assertEq(token.balanceOf(alice) - aliceBefore, 45 ether);

        // researcher slashed: nothing
        vm.prank(researcher);
        vm.expectRevert(bytes("nothing to claim"));
        market.claim(id);

        // bob losing YES: nothing
        vm.prank(bob);
        vm.expectRevert(bytes("nothing to claim"));
        market.claim(id);

        // alice staked NO into an empty market (entry 50%) and it closed at 30/35 = 85.7%,
        // so movement = 0.357 — consensus travelled a long way toward her.
        // 5 * sqrt(30)=5 * contest 0.2857 * 0.357 = 2.55 -> 2
        assertEq(rep.repOf(alice), 2);
        assertEq(token.balanceOf(address(market)), 0);
    }

    function test_noReviews_returnsSubmitterStake() public {
        uint256 id = _submit(10 ether);
        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);
        NotchMarket.Artifact memory a = market.getArtifact(id);
        assertTrue(a.outcomeYes); // tie -> YES

        uint256 rBefore = token.balanceOf(researcher);
        vm.prank(researcher);
        market.claim(id);
        assertEq(token.balanceOf(researcher) - rBefore, 10 ether); // exactly stake back
        assertEq(token.balanceOf(address(market)), 0);
    }

    function test_cannotReviewAfterDeadline() public {
        uint256 id = _submit(10 ether);
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        vm.expectRevert(bytes("review closed"));
        market.review(id, true, 1 ether);
    }

    function test_cannotResolveEarly() public {
        uint256 id = _submit(10 ether);
        vm.expectRevert(bytes("still reviewing"));
        market.resolve(id);
    }

    function test_cannotClaimTwice() public {
        uint256 id = _submit(10 ether);
        vm.prank(alice);
        market.review(id, true, 10 ether);
        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);
        vm.prank(alice);
        market.claim(id);
        vm.prank(alice);
        vm.expectRevert(bytes("nothing to claim"));
        market.claim(id);
    }

    function test_minReviewerRepGate() public {
        // datanet requiring 5 rep to review
        uint256 gated = market.createDatanet("Experts only", "gated", 10 ether, 3 days, 5);
        vm.prank(researcher);
        uint256 id = market.submitArtifact(gated, "t", "uri", CONTENT_HASH, 10 ether);

        vm.prank(alice); // alice has 0 rep
        vm.expectRevert(bytes("insufficient rep"));
        market.review(id, true, 1 ether);
    }

    function test_onlyOwnerCreatesDatanet() public {
        vm.prank(alice);
        vm.expectRevert();
        market.createDatanet("x", "y", 1 ether, 1 days, 0);
    }
}
