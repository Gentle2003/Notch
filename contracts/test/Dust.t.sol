// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Probes whether the pro-rata split leaves unclaimable dust when the
///         losing pool does NOT divide evenly across the winning side.
contract DustTest is Test {

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

    address researcher = makeAddr("researcher");
    address a = makeAddr("a");
    address b = makeAddr("b");
    address c = makeAddr("c");

    uint256 dn;

    function setUp() public {
        token = new NotchToken();
        rep = new Reputation(address(this));
        market = new NotchMarket(address(token), address(rep), address(this));
        rep.initializeMarket(address(market));
        dn = market.createDatanet("d", "d", 1, 3 days, 0);

        address[4] memory who = [researcher, a, b, c];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 10_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    /// Awkward ratio: YES wins (yes=2 >= no=2, ties go YES), so winWeight is
    /// submitStake(1) + yesStake(2) = 3 and losePool is 2. Each winner's pro-rata cut
    /// truncates to 2*1/3 = 0, which previously stranded the whole 2 wei losing pool.
    /// The final winner to claim now sweeps the remainder, so it drains to zero.
    function test_noDustOnUnevenSplit() public {
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", CONTENT_HASH, 1 wei);

        vm.prank(a);
        market.review(id, true, 1 wei); // YES
        vm.prank(b);
        market.review(id, true, 1 wei); // YES
        vm.prank(c);
        market.review(id, false, 2 wei); // NO — the losing pool

        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);

        vm.prank(researcher);
        market.claim(id);
        vm.prank(a);
        market.claim(id);
        vm.prank(b);
        market.claim(id);
        vm.prank(c);
        try market.claim(id) {} catch {}

        uint256 residual = token.balanceOf(address(market));
        emit log_named_uint("residual wei stuck in contract", residual);
        assertEq(residual, 0, "remainder must be swept by the final claimer");
    }

    /// Sanity: an evenly-divisible split really does drain to zero.
    function test_noDustOnEvenSplit() public {
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", CONTENT_HASH, 10 ether);

        vm.prank(a);
        market.review(id, true, 20 ether);
        vm.prank(c);
        market.review(id, false, 12 ether);

        vm.warp(block.timestamp + 3 days);
        market.resolve(id);
        _finalizeArtifact(id);

        vm.prank(researcher);
        market.claim(id);
        vm.prank(a);
        market.claim(id);
        vm.prank(c);
        try market.claim(id) {} catch {}

        assertEq(token.balanceOf(address(market)), 0);
    }
}
