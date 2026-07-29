// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Reputation} from "../src/Reputation.sol";
import {NotchMarket} from "../src/NotchMarket.sol";

/// @notice Mainnet deployment. Deliberately smaller than the testnet script: the
///         collateral is an existing token, so NotchToken is not deployed, and
///         TestnetFaucet is never deployed outside a testnet.
///
///         Set COLLATERAL to the token the market should escrow. It is immutable once
///         deployed — the market can never be repointed at a different asset, which is
///         the point: people staking need to know what they are staking.
///
/// Usage:
///   COLLATERAL=0x... PRIVATE_KEY=0x... forge script script/DeployMainnet.s.sol \
///     --rpc-url https://rpc.mainnet.chain.robinhood.com --broadcast
contract DeployMainnet is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address collateral = vm.envAddress("COLLATERAL");

        // Refuse to deploy against something that is not a token, rather than discovering
        // it after the address is immutable.
        uint8 dec = IERC20Metadata(collateral).decimals();
        uint256 supply = IERC20Metadata(collateral).totalSupply();
        require(supply > 0, "collateral has no supply");
        console2.log("collateral:", collateral);
        console2.log("  symbol:", IERC20Metadata(collateral).symbol());
        console2.log("  decimals:", dec);

        vm.startBroadcast(pk);

        Reputation rep = new Reputation(deployer);
        NotchMarket market = new NotchMarket(collateral, address(rep), deployer);
        rep.initializeMarket(address(market));

        // Stakes are denominated in the collateral, so these numbers mean whole tokens.
        // Revisit them against real price before inviting anyone in.
        uint256 unit = 10 ** dec;
        market.createDatanet(
            "RWA Research",
            "Deep dives on tokenized real-world assets: yield, custody, collateral quality.",
            25 * unit,
            3 days,
            0
        );
        market.createDatanet(
            "Tokenized Stock Theses",
            "Bull/bear analyses of tokenized equities trading on Robinhood Chain.",
            25 * unit,
            2 days,
            0
        );
        market.createDatanet(
            "Meme Signal",
            "Is this meme-coin thesis high-signal or noise? Reviewers stake to grade it.",
            10 * unit,
            1 days,
            0
        );
        market.createDatanet(
            "Protocol & Launchpad",
            "Tokenomics, emissions, fee design and launch quality for new protocols. Reviewers should be able to read a contract or a fee model.",
            25 * unit,
            3 days,
            0
        );
        market.createDatanet(
            "Expert Desk",
            "Reputation-gated: only proven analysts (>= 50 Reps) may review here.",
            50 * unit,
            3 days,
            50
        );

        vm.stopBroadcast();

        console2.log("Reputation:", address(rep));
        console2.log("NotchMarket:", address(market));
        console2.log("deployer/owner:", deployer);
        console2.log("collateralUnit:", market.collateralUnit());
        console2.log("minChallengeBond:", market.minChallengeBond());

        string memory obj = "mainnet";
        vm.serializeAddress(obj, "Reputation", address(rep));
        vm.serializeAddress(obj, "NotchToken", collateral);
        vm.serializeAddress(obj, "deployer", deployer);
        string memory json = vm.serializeAddress(obj, "NotchMarket", address(market));
        vm.writeJson(json, string.concat("deployments/", vm.toString(block.chainid), ".json"));
    }
}
