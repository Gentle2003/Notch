// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Regression guard for the reputation-farming hole.
///
///         Before the earn rule was fixed, an uncontested artifact refunded every
///         participant in full and still paid Reps proportional to stake — so reputation
///         cost nothing and converted from capital at a fixed rate. These tests pin the
///         fix: Reps require genuine opposition, and scale with sqrt(stake).
contract RepFarmTest is Test {

    /// Appeals: resolve() only posts a provisional outcome. Claims unlock once the
    /// challenge window has elapsed and someone finalises it.
    function _finalizeArtifact(uint256 id) internal {
        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);
    }
    bytes32 constant H = keccak256("x");
    NotchToken token;
    Reputation rep;
    NotchMarket market;

    address attacker = makeAddr("attacker");
    address sock = makeAddr("sock"); // second wallet the attacker controls
    address honest = makeAddr("honest");
    uint256 dn;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.setMarket(address(market), true);
        dn = market.createDatanet("d", "d", 1 ether, 3 days, 0);

        address[3] memory who = [attacker, sock, honest];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 100_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    /// The old farm: submit to yourself, back it from a second wallet, nobody opposes.
    /// Tokens still come back in full — the contract is not punitive — but the contest
    /// factor is zero, so the run yields no reputation at all.
    function test_uncontestedArtifactEarnsNoReps() public {
        uint256 attackerStart = token.balanceOf(attacker);
        uint256 sockStart = token.balanceOf(sock);

        vm.prank(attacker);
        uint256 id = market.submitArtifact(dn, "anything", "uri", H, 1 ether);
        vm.prank(sock);
        market.review(id, true, 50_000 ether);

        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);
        vm.prank(attacker);
        market.claim(id);
        vm.prank(sock);
        market.claim(id);

        assertEq(token.balanceOf(attacker), attackerStart, "stake is still refunded");
        assertEq(token.balanceOf(sock), sockStart, "stake is still refunded");

        assertEq(rep.repOf(sock), 0, "no opposition, no reputation");
        assertEq(rep.repOf(attacker), 0, "no opposition, no reputation");
    }

    /// A one-sided blowout is nearly as cheap to manufacture, so it must pay nearly
    /// nothing even though it technically had an opponent.
    function test_blowoutEarnsAlmostNothing() public {
        vm.prank(attacker);
        uint256 id = market.submitArtifact(dn, "a", "uri", H, 1 ether);
        vm.prank(sock);
        market.review(id, true, 10_000 ether);
        vm.prank(honest);
        market.review(id, false, 10 ether); // token opposition

        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);
        vm.prank(sock);
        market.claim(id);

        // contest factor ~ 2*10/10010 = 0.002, so 100 reps collapses to 0
        assertEq(rep.repOf(sock), 0, "a token opponent must not unlock full reps");
    }

    /// Capital no longer converts to reputation at a fixed rate: 100x the stake earns
    /// 10x the Reps, so buying influence is quadratically more expensive.
    function test_repsScaleWithSqrtOfStake() public {
        uint256 big = _contestedRun(5_000 ether, sock); // stakes 10,000
        uint256 small = _contestedRun(50 ether, honest); // stakes 100

        emit log_named_uint("reps for 10,000 stake", big);
        emit log_named_uint("reps for 100 stake", small);

        assertGt(big, 0, "a real call must earn something");
        // sqrt scaling holds to within integer truncation at each step (222 vs 220).
        assertApproxEqRel(big, small * 10, 0.02e18, "100x capital -> ~10x reps");
    }

    /// Runs a perfectly contested artifact where `winner` takes the YES side and an equal
    /// NO stake opposes it, then returns the Reps the winner earned.
    function _contestedRun(uint256 amount, address winner) internal returns (uint256) {
        address opponent = makeAddr(string(abi.encodePacked("opp", amount)));
        token.transfer(opponent, amount);
        vm.prank(opponent);
        token.approve(address(market), type(uint256).max);

        vm.prank(attacker);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, 1 ether);

        // Opposition leads first, then the winner takes twice that. The shape is
        // identical at every scale — entry 0%, final 66.7%, contest 66.7% — so contest
        // and movement cancel out and only sqrt(stake) can differ.
        vm.prank(opponent);
        market.review(id, false, amount);
        vm.prank(winner);
        market.review(id, true, amount * 2);

        // Warp to this artifact's own deadline rather than doing arithmetic on
        // block.timestamp, so a second run in the same test can't under-warp.
        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
        _finalizeArtifact(id);

        uint256 before = rep.repOf(winner);
        vm.prank(winner);
        market.claim(id);
        return rep.repOf(winner) - before;
    }
}
