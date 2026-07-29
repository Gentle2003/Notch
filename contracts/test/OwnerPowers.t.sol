// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// A contract an owner could authorise to mint reputation out of nothing.
contract RogueMinter {
    Reputation public rep;
    constructor(Reputation r) { rep = r; }
    function mint(address to, uint256 amount) external { rep.award(to, amount); }
}

/// @notice What the owner key can still do today, demonstrated rather than asserted.
///         These are not bugs — they are the powers that need a multisig and a timelock
///         in front of them before real money is involved.
contract OwnerPowersTest is Test {
    NotchToken token;
    Reputation rep;
    NotchMarket market;
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.setMarket(address(market), true);
    }

    /// Step 7: setMarket can authorise ANY contract to mint unlimited Reps. Reputation
    /// is meant to be unbuyable; this makes it issuable by decree.
    function test_ownerCanAuthoriseUnlimitedRepMinting() public {
        assertEq(rep.repOf(attacker), 0);

        RogueMinter rogue = new RogueMinter(rep);
        rep.setMarket(address(rogue), true); // one owner call
        rogue.mint(attacker, 1_000_000);

        assertEq(rep.repOf(attacker), 1_000_000, "reputation minted from nothing");
        // And it converts straight into vote weight.
        assertEq(market.repMultiplierBps(rep.repOf(attacker)), market.repMultCapBps());
    }

    /// Step 6: the multiplier cap is read live, so changing it re-weights every vote in
    /// every open market instantly — no warning, no delay.
    function test_ownerCanReweightEveryOpenMarketInstantly() public {
        RogueMinter rogue = new RogueMinter(rep);
        rep.setMarket(address(rogue), true);
        rogue.mint(attacker, 2_500);

        assertEq(market.repMultiplierBps(2_500), 15_000, "1.5x under the bootstrap cap");

        market.setRepMultCapBps(40_000); // one owner call
        assertEq(market.repMultiplierBps(2_500), 40_000, "now 4x, applied retroactively");
    }

    /// Reps really are one-shot per artifact — the user's read was right.
    function test_repRateChangeCannotRewriteAlreadyEarnedReps() public {
        RogueMinter rogue = new RogueMinter(rep);
        rep.setMarket(address(rogue), true);
        rogue.mint(attacker, 100);

        market.setRepRate(1_000_000);
        assertEq(rep.repOf(attacker), 100, "already-earned Reps are untouched");
    }
}
