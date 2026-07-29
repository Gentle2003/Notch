// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Runs the whole market against the real NOTCH token on a Robinhood mainnet
///         fork, before anything is deployed there for real. Reading a token's interface
///         is not the same as watching escrow settle against it.
contract ForkIntegrationTest is Test {
    address constant NOTCH = 0xFa65fA4BBB3B4806D923be4E210e6860846c8070;
    address constant WHALE = 0xb67D949770518324DcEACB4B5E3463bCea117413;
    bytes32 constant H = keccak256("analysis");

    IERC20 token;
    Reputation rep;
    NotchMarket market;

    address researcher = makeAddr("researcher");
    address yes = makeAddr("yes");
    address no = makeAddr("no");

    function setUp() public {
        vm.createSelectFork("https://rpc.mainnet.chain.robinhood.com");
        token = IERC20(NOTCH);

        rep = new Reputation(address(this));
        market = new NotchMarket(NOTCH, address(rep), address(this));
        rep.initializeMarket(address(market));

        // Fund participants from the real holder.
        address[3] memory who = [researcher, yes, no];
        for (uint256 i; i < who.length; i++) {
            vm.prank(WHALE);
            token.transfer(who[i], 100_000 ether);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }
    }

    /// The market must read 18 decimals off the real token, not assume them.
    function test_marketReadsRealTokenDecimals() public view {
        assertEq(market.collateralUnit(), 1e18, "NOTCH is 18-decimal");
        assertEq(market.minChallengeBond(), 10e18, "bond floor is 10 whole NOTCH");
    }

    /// Full lifecycle against real mainnet state: submit, contest, resolve, appeal
    /// window, finalise, claim — and the escrow must end empty.
    function test_fullLifecycleAgainstRealToken() public {
        uint256 dn = market.createDatanet("RWA Research", "d", 25 ether, 3 days, 0);

        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "Real-token dry run", "ipfs://cid", H, 25 ether);

        // NO leads, then YES overtakes — a genuine contest with real movement.
        vm.prank(no);
        market.review(id, false, 400 ether);
        vm.prank(yes);
        market.review(id, true, 900 ether);

        assertEq(token.balanceOf(address(market)), 1_325 ether, "escrow holds every stake");

        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
        assertTrue(market.getArtifact(id).outcomeYes);

        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);

        uint256 yesBefore = token.balanceOf(yes);
        vm.prank(yes);
        market.claim(id);
        vm.prank(researcher);
        market.claim(id);
        vm.prank(no);
        try market.claim(id) {} catch {}

        assertGt(token.balanceOf(yes) - yesBefore, 900 ether, "winner takes stake plus pool");
        assertEq(token.balanceOf(address(market)), 0, "escrow drains completely");
        assertGt(rep.repOf(yes), 0, "reputation accrues against the real token");
    }

    /// Appeals must work against the real token too.
    function test_appealAgainstRealToken() public {
        uint256 dn = market.createDatanet("d", "d", 25 ether, 3 days, 0);
        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, 25 ether);

        vm.prank(no);
        market.review(id, false, 100 ether);
        vm.prank(yes);
        market.review(id, true, 500 ether);

        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
        assertTrue(market.getArtifact(id).outcomeYes, "capital wins round 0");

        vm.prank(no);
        market.challenge(id);
        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
        assertFalse(market.getArtifact(id).outcomeYes, "appeal corrects it");
    }
}
