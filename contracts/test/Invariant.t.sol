// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Drives the market with randomised traffic so the invariants below are checked
///         against sequences nobody thought to write by hand. The dust bug survived
///         eleven passing unit tests because every number in them divided evenly — this
///         handler exists so that class of mistake cannot repeat.
contract Handler is Test {
    NotchToken public token;
    NotchMarket public market;
    uint256 public dn;

    address[] public actors;

    /// Ghost accounting, maintained independently of the contract.
    uint256 public totalIn;
    uint256 public totalOut;

    uint256[] public liveArtifacts;

    constructor(NotchToken t, NotchMarket m, uint256 dn_, address[] memory a) {
        token = t;
        market = m;
        dn = dn_;
        actors = a;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function submit(uint256 seed, uint96 stake) public {
        address who = _actor(seed);
        uint256 amount = bound(uint256(stake), 1 ether, 5_000 ether);
        if (token.balanceOf(who) < amount) return;

        vm.prank(who);
        try market.submitArtifact(dn, "t", "uri", bytes32(0), amount) returns (uint256 id) {
            totalIn += amount;
            liveArtifacts.push(id);
        } catch {}
    }

    function review(uint256 seed, uint256 idxSeed, bool support, uint96 stake) public {
        if (liveArtifacts.length == 0) return;
        address who = _actor(seed);
        uint256 id = liveArtifacts[idxSeed % liveArtifacts.length];
        uint256 amount = bound(uint256(stake), 1 ether, 5_000 ether);
        if (token.balanceOf(who) < amount) return;

        vm.prank(who);
        try market.review(id, support, amount) {
            totalIn += amount;
        } catch {}
    }

    function resolve(uint256 idxSeed) public {
        if (liveArtifacts.length == 0) return;
        uint256 id = liveArtifacts[idxSeed % liveArtifacts.length];
        vm.warp(market.getArtifact(id).reviewDeadline);
        try market.resolve(id) {} catch {}
    }

    function claim(uint256 seed, uint256 idxSeed) public {
        if (liveArtifacts.length == 0) return;
        address who = _actor(seed);
        uint256 id = liveArtifacts[idxSeed % liveArtifacts.length];

        uint256 before = token.balanceOf(who);
        vm.prank(who);
        try market.claim(id) {
            totalOut += token.balanceOf(who) - before;
        } catch {}
    }

    function artifactCount() external view returns (uint256) {
        return liveArtifacts.length;
    }
}

contract InvariantTest is Test {

    /// Appeals: resolve() only posts a provisional outcome. Claims unlock once the
    /// challenge window has elapsed and someone finalises it.
    function _finalizeArtifact(uint256 id) internal {
        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);
    }
    NotchToken token;
    Reputation rep;
    NotchMarket market;
    Handler handler;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.initializeMarket(address(market));
        // Widen the multiplier cap so reputation weighting is actually exercised.
        // Cap changes are timelocked; fast-forward past the delay to apply it.
        market.proposeRepMultCapBps(40_000);
        vm.warp(block.timestamp + market.ADMIN_DELAY());
        market.executeRepMultCapBps();
        uint256 dn = market.createDatanet("d", "d", 1 ether, 3 days, 0);

        address[] memory actors = new address[](4);
        for (uint256 i; i < 4; i++) {
            actors[i] = address(uint160(0xA11CE + i));
            token.transfer(actors[i], 200_000 ether);
        }

        handler = new Handler(token, market, dn, actors);

        for (uint256 i; i < 4; i++) {
            vm.prank(actors[i]);
            token.approve(address(market), type(uint256).max);
        }

        targetContract(address(handler));
    }

    /// The contract must hold exactly what it has taken in and not yet paid out. If this
    /// ever breaks, the market is either insolvent or minting money.
    function invariant_escrowMatchesLedger() public view {
        assertEq(
            token.balanceOf(address(market)),
            handler.totalIn() - handler.totalOut(),
            "escrow drifted from the ledger"
        );
    }

    /// Payouts can never exceed what participants staked.
    function invariant_neverPaysOutMoreThanTakenIn() public view {
        assertLe(handler.totalOut(), handler.totalIn(), "market paid out more than it held");
    }
}

/// @notice Property tests over randomised single-artifact scenarios. These target the dust
///         class directly: a fully resolved and fully claimed artifact must leave nothing.
contract PayoutFuzzTest is Test {

    /// Appeals: resolve() only posts a provisional outcome. Claims unlock once the
    /// challenge window has elapsed and someone finalises it.
    function _finalizeArtifact(uint256 id) internal {
        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);
    }
    NotchToken token;
    Reputation rep;
    NotchMarket market;

    address researcher = makeAddr("researcher");
    address yesA = makeAddr("yesA");
    address yesB = makeAddr("yesB");
    address noA = makeAddr("noA");
    uint256 dn;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.initializeMarket(address(market));
        // Cap changes are timelocked; fast-forward past the delay to apply it.
        market.proposeRepMultCapBps(40_000);
        vm.warp(block.timestamp + market.ADMIN_DELAY());
        market.executeRepMultCapBps();
        dn = market.createDatanet("d", "d", 1, 3 days, 0);

        address[4] memory who = [researcher, yesA, yesB, noA];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 200_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    /// Whatever the split, once every participant has claimed, the escrow for that
    /// artifact is empty. Awkward ratios that truncate are exactly the interesting case.
    function testFuzz_artifactAlwaysDrainsToZero(
        uint96 submitStake,
        uint96 yesOne,
        uint96 yesTwo,
        uint96 noOne
    ) public {
        uint256 s = bound(uint256(submitStake), 1, 50_000 ether);
        uint256 y1 = bound(uint256(yesOne), 1, 50_000 ether);
        uint256 y2 = bound(uint256(yesTwo), 1, 50_000 ether);
        uint256 n1 = bound(uint256(noOne), 1, 50_000 ether);

        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", bytes32(0), s);

        vm.prank(yesA);
        market.review(id, true, y1);
        vm.prank(yesB);
        market.review(id, true, y2);
        vm.prank(noA);
        market.review(id, false, n1);

        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
        _finalizeArtifact(id);

        address[4] memory all = [researcher, yesA, yesB, noA];
        for (uint256 i; i < all.length; i++) {
            vm.prank(all[i]);
            try market.claim(id) {} catch {}
        }

        assertEq(token.balanceOf(address(market)), 0, "escrow must drain completely");
    }

    /// The multiplier is monotonic, never below face value, and never above the cap.
    function testFuzz_repMultiplierIsBounded(uint256 reps, uint256 more) public view {
        reps = bound(reps, 0, 1e12);
        more = bound(more, 0, 1e12);

        uint256 m = market.repMultiplierBps(reps);
        assertGe(m, 10_000, "stake must never count below face value");
        assertLe(m, market.repMultCapBps(), "multiplier must respect the cap");
        assertGe(market.repMultiplierBps(reps + more), m, "more reps must never mean less weight");
    }

    /// The contest factor stays in range and is zero exactly when a side went unopposed —
    /// the property that stops reputation being farmed.
    function testFuzz_contestFactorBounds(uint256 wYes, uint256 wNo) public view {
        wYes = bound(wYes, 0, 1e30);
        wNo = bound(wNo, 0, 1e30);

        uint256 c = market.contestFactorBps(wYes, wNo);
        assertLe(c, 10_000, "contest factor cannot exceed 1.0");
        if (wYes == 0 || wNo == 0) {
            assertEq(c, 0, "an unopposed side must yield no reputation");
        }
    }
}
