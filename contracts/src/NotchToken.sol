// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title NotchToken
/// @notice Testnet collateral token staked by researchers and reviewers in Notch quality
///         markets. Ships with a rate-limited public faucet so testers can self-serve stake.
///         On a production deployment this would be replaced by a real collateral asset
///         (e.g. bridged USDG / Robinhood ETH) and the faucet removed.
contract NotchToken is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 1_000 ether;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    mapping(address => uint256) public lastFaucet;

    constructor() ERC20("Notch Stake", "NOTCH") {
        // Seed the deployer for scripted setup / house liquidity.
        _mint(msg.sender, 1_000_000 ether);
    }

    /// @notice Mint testnet stake to the caller, once per cooldown window.
    function faucet() external {
        require(block.timestamp >= lastFaucet[msg.sender] + FAUCET_COOLDOWN, "faucet: cooldown");
        lastFaucet[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
