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

/// @notice The owner key here is the deployer — the team, never a researcher or reviewer.
///         These tests pin what that key can and cannot do now that the dangerous dials
///         are timelocked: the powers still exist, but they can no longer land silently.
///         A multisig on top is the remaining piece.
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
        rep.initializeMarket(address(market));
    }

    /// Step 7: setMarket can authorise ANY contract to mint unlimited Reps. Reputation
    /// is meant to be unbuyable; this makes it issuable by decree.
    function test_ownerCanAuthoriseUnlimitedRepMinting() public {
        assertEq(rep.repOf(attacker), 0);

        RogueMinter rogue = new RogueMinter(rep);

        // The one-shot bootstrap is spent, so a new minter can only be queued.
        rep.proposeMarket(address(rogue), true);
        vm.expectRevert(bytes("rep: not market"));
        rogue.mint(attacker, 1_000_000);

        // Executing early is refused.
        vm.expectRevert(bytes("timelocked"));
        rep.executeMarketChange();

        // After the delay it lands — the power still exists, it is just no longer silent.
        vm.warp(block.timestamp + rep.ADMIN_DELAY());
        rep.executeMarketChange();
        rogue.mint(attacker, 1_000_000);
        assertEq(rep.repOf(attacker), 1_000_000, "still possible, but 48h in the open");
    }

    /// The cap is read live on every vote, so widening it re-weights open markets. It
    /// can still be done — but only after the delay, and visibly.
    function test_capChangeCannotLandSilently() public {
        assertEq(market.repMultiplierBps(2_500), 15_000, "1.5x under the bootstrap cap");

        market.proposeRepMultCapBps(40_000);
        assertEq(market.repMultiplierBps(2_500), 15_000, "proposing changes nothing yet");

        vm.expectRevert(bytes("timelocked"));
        market.executeRepMultCapBps();

        vm.warp(block.timestamp + market.ADMIN_DELAY());
        market.executeRepMultCapBps();
        assertEq(market.repMultiplierBps(2_500), 40_000, "applies only after the delay");
    }

    /// The bootstrap is one-shot: it cannot be reused to slip in a second minter.
    function test_marketBootstrapCannotBeReused() public {
        RogueMinter rogue = new RogueMinter(rep);
        vm.expectRevert(bytes("already initialised"));
        rep.initializeMarket(address(rogue));
    }

    /// Changing the rate never rewrites reputation already awarded.
    function test_repRateChangeCannotRewriteHistory() public {
        market.setRepRate(1_000_000);
        assertEq(rep.repOf(attacker), 0, "rate changes are forward-looking only");
    }
}
