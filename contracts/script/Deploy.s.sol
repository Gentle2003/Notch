// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {NotchToken} from "../src/NotchToken.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Deploys the Notch stack, wires reputation permissions, and seeds starter datanets.
///         Writes deployed addresses to deployments/<chainId>.json for the web app to consume.
///
/// Usage:
///   forge script script/Deploy.s.sol --rpc-url <rpc> --broadcast --private-key <key>
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        NotchToken token = new NotchToken();
        Reputation rep = new Reputation(deployer);
        NotchMarket market = new NotchMarket(address(token), address(rep), deployer);
        rep.setMarket(address(market), true);

        // Starter datanets tuned for the RWA / meme research narrative.
        // (name, description, minSubmitStake, reviewWindow, minReviewerRep)
        market.createDatanet(
            "RWA Research",
            "Deep dives on tokenized real-world assets: yield, custody, collateral quality.",
            25 ether,
            3 days,
            0
        );
        market.createDatanet(
            "Tokenized Stock Theses",
            "Bull/bear analyses of tokenized equities trading on Robinhood Chain.",
            25 ether,
            2 days,
            0
        );
        market.createDatanet(
            "Meme Signal",
            "Is this meme-coin thesis high-signal or noise? Reviewers stake to grade it.",
            10 ether,
            1 days,
            0
        );
        market.createDatanet(
            "Expert Desk",
            "Reputation-gated: only proven analysts (>= 50 Reps) may review here.",
            50 ether,
            3 days,
            50
        );

        vm.stopBroadcast();

        console2.log("NotchToken:", address(token));
        console2.log("Reputation:", address(rep));
        console2.log("NotchMarket:", address(market));
        console2.log("deployer:", deployer);

        _write(address(token), address(rep), address(market), deployer);
    }

    function _write(address token, address rep, address market, address deployer) internal {
        string memory obj = "deployment";
        vm.serializeAddress(obj, "NotchToken", token);
        vm.serializeAddress(obj, "Reputation", rep);
        vm.serializeAddress(obj, "deployer", deployer);
        string memory json = vm.serializeAddress(obj, "NotchMarket", market);
        string memory path =
            string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
    }
}
