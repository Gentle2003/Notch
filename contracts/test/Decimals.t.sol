// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// A collateral token with configurable decimals, e.g. USDC-style 6.
contract MockToken is ERC20 {
    uint8 private immutable _dec;

    constructor(uint8 dec_) ERC20("Mock", "MOCK") {
        _dec = dec_;
        _mint(msg.sender, 1_000_000 * 10 ** dec_);
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }
}

/// @notice The Rep award divides stake down to whole tokens before taking a square root.
///         Assuming 18 decimals silently zeroed reputation for any smaller token.
contract DecimalsTest is Test {
    bytes32 constant H = keccak256("x");

    address researcher = makeAddr("researcher");
    address yes = makeAddr("yes");
    address no = makeAddr("no");

    /// Runs one contested artifact against a token with `dec` decimals and returns the
    /// Reps the winning reviewer earned.
    function _run(uint8 dec) internal returns (uint256) {
        vm.warp(1_700_000_000);
        MockToken token = new MockToken(dec);
        Reputation rep = new Reputation(address(this));
        NotchMarket market = new NotchMarket(address(token), address(rep), address(this));
        rep.initializeMarket(address(market));

        uint256 unit = 10 ** dec;
        uint256 dn = market.createDatanet("d", "d", unit, 3 days, 0);

        address[3] memory who = [researcher, yes, no];
        for (uint256 i; i < who.length; i++) {
            token.transfer(who[i], 100_000 * unit);
            vm.prank(who[i]);
            token.approve(address(market), type(uint256).max);
        }

        vm.prank(researcher);
        uint256 id = market.submitArtifact(dn, "t", "uri", H, unit);
        // NO leads, then YES takes it — real contest, real movement.
        vm.prank(no);
        market.review(id, false, 500 * unit);
        vm.prank(yes);
        market.review(id, true, 1_000 * unit);

        vm.warp(market.getArtifact(id).reviewDeadline);
        market.resolve(id);
        vm.warp(block.timestamp + market.CHALLENGE_WINDOW());
        market.finalize(id);

        vm.prank(yes);
        market.claim(id);
        return rep.repOf(yes);
    }

    /// Identical stake in whole-token terms must earn the same reputation regardless of
    /// how many decimals the collateral happens to use.
    function test_repsAreIndependentOfTokenDecimals() public {
        uint256 r18 = _run(18);
        uint256 r6 = _run(6);
        uint256 r8 = _run(8);

        emit log_named_uint("18 decimals", r18);
        emit log_named_uint(" 8 decimals", r8);
        emit log_named_uint(" 6 decimals", r6);

        assertGt(r18, 0, "18-decimal collateral must earn Reps");
        assertEq(r6, r18, "6-decimal collateral must earn the same");
        assertEq(r8, r18, "8-decimal collateral must earn the same");
    }

    /// The appeal floor is denominated in whole tokens, not wei.
    function test_minChallengeBondScalesToCollateral() public {
        MockToken t6 = new MockToken(6);
        Reputation rep = new Reputation(address(this));
        NotchMarket m6 = new NotchMarket(address(t6), address(rep), address(this));
        assertEq(m6.collateralUnit(), 1e6);
        assertEq(m6.minChallengeBond(), 10 * 1e6, "10 whole tokens, not 10e18 wei");
    }
}
