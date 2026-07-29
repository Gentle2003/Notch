// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Can reputation be farmed without risking anything?
contract RepFarmTest is Test {
    bytes32 constant H = keccak256("x");
    NotchToken token;
    Reputation rep;
    NotchMarket market;

    address attacker = makeAddr("attacker");
    address sock = makeAddr("sock"); // second wallet the attacker controls
    uint256 dn;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.setMarket(address(market), true);
        dn = market.createDatanet("d", "d", 1 ether, 3 days, 0);

        address[2] memory who = [attacker, sock];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 100_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    /// An uncontested artifact always resolves YES (0 >= 0), so nobody loses and
    /// everyone on the winning side is paid Reps proportional to their stake.
    /// The attacker submits to themselves, stakes big from a second wallet, and
    /// walks away with the full stake AND the reputation.
    function test_reputationIsFreeToFarm() public {
        uint256 attackerStart = token.balanceOf(attacker);
        uint256 sockStart = token.balanceOf(sock);

        vm.prank(attacker);
        uint256 id = market.submitArtifact(dn, "anything", "uri", H, 1 ether);

        // Second wallet backs it. No opposition exists, so none is possible to lose to.
        vm.prank(sock);
        market.review(id, true, 50_000 ether);

        vm.warp(block.timestamp + 3 days);
        market.resolve(id);

        vm.prank(attacker);
        market.claim(id);
        vm.prank(sock);
        market.claim(id);

        emit log_named_uint("attacker reps", rep.repOf(attacker));
        emit log_named_uint("sock reps", rep.repOf(sock));
        emit log_named_int(
            "attacker net tokens", int256(token.balanceOf(attacker)) - int256(attackerStart)
        );
        emit log_named_int("sock net tokens", int256(token.balanceOf(sock)) - int256(sockStart));

        // Nobody lost a single token.
        assertEq(token.balanceOf(attacker), attackerStart, "attacker paid nothing");
        assertEq(token.balanceOf(sock), sockStart, "sock paid nothing");

        // Yet both walked away with reputation, sized by how much capital they moved.
        assertEq(rep.repOf(sock), 50_000, "reps scale directly with stake");
        assertGt(rep.repOf(sock), 0);
    }

    /// Reps are minted in direct proportion to stake, so capital converts to
    /// reputation at a fixed rate — reputation is not independent of money.
    function test_repsAreProportionalToCapital() public {
        vm.prank(attacker);
        uint256 a = market.submitArtifact(dn, "a", "uri", H, 1 ether);
        vm.prank(sock);
        market.review(a, true, 1_000 ether);

        vm.warp(block.timestamp + 3 days);
        market.resolve(a);
        vm.prank(sock);
        market.claim(a);

        uint256 repsFor1000 = rep.repOf(sock);
        assertEq(repsFor1000, 1_000, "10x the stake would earn 10x the reps");
    }
}
