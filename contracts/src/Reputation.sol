// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Reputation
/// @notice Non-transferable, on-chain reputation ("Reps") earned by correctly staking on
///         research quality. Only authorized markets may award Reps. Reps gate access to
///         higher-trust reviewer roles (a datanet may require a minimum Rep to review).
///
///         Reps are deliberately soulbound: there are no transfer/approve functions, so
///         reputation cannot be bought, sold, or delegated — it must be earned.
contract Reputation is Ownable {
    /// @notice Reputation balance per account.
    mapping(address => uint256) public repOf;

    /// @notice Markets allowed to mint Reps.
    mapping(address => bool) public isMarket;

    /// @notice Cumulative Reps ever minted (for a global leaderboard denominator).
    uint256 public totalRep;

    event MarketSet(address indexed market, bool allowed);
    event RepAwarded(address indexed account, uint256 amount, uint256 newBalance);

    constructor(address owner_) Ownable(owner_) {}

    modifier onlyMarket() {
        require(isMarket[msg.sender], "rep: not market");
        _;
    }

    /// @notice Authorize (or revoke) a market contract that may award Reps.
    function setMarket(address market, bool allowed) external onlyOwner {
        isMarket[market] = allowed;
        emit MarketSet(market, allowed);
    }

    /// @notice Award Reps to an account. Callable only by authorized markets.
    function award(address account, uint256 amount) external onlyMarket {
        if (amount == 0) return;
        repOf[account] += amount;
        totalRep += amount;
        emit RepAwarded(account, amount, repOf[account]);
    }
}
