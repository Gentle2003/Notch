// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title NotchToken
/// @notice Collateral staked by researchers and reviewers in Notch quality markets.
///
///         Fixed supply, minted once at deployment. There is no mint function and no
///         faucet: an earlier version let any address mint itself 1,000 tokens a day,
///         which is harmless on a testnet and unbounded inflation anywhere else.
///         Testnet distribution is handled by `TestnetFaucet`, which hands out tokens it
///         already holds and is simply not deployed to mainnet.
contract NotchToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;

    constructor() ERC20("Notch Stake", "NOTCH") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
