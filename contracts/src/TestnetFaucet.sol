// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TestnetFaucet
/// @notice Hands out NOTCH so people can try the market without being funded by hand.
///
///         It can only give away what it already holds — it has no minting power over the
///         token, so the worst case is that it runs dry. That is the whole point of
///         separating it: the faucet used to live inside the token as a public mint,
///         which made unbounded inflation a property of the asset itself. Simply do not
///         deploy this contract to mainnet.
contract TestnetFaucet is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 public dripAmount = 1_000 ether;
    uint256 public cooldown = 1 days;

    mapping(address => uint256) public lastDrip;

    event Dripped(address indexed to, uint256 amount);

    constructor(address token_, address owner_) Ownable(owner_) {
        token = IERC20(token_);
    }

    function drip() external {
        require(block.timestamp >= lastDrip[msg.sender] + cooldown, "faucet: cooldown");
        uint256 amount = dripAmount;
        require(token.balanceOf(address(this)) >= amount, "faucet: empty");

        lastDrip[msg.sender] = block.timestamp;
        token.safeTransfer(msg.sender, amount);
        emit Dripped(msg.sender, amount);
    }

    /// @notice Seconds until `who` may drip again; 0 if they can now.
    function cooldownRemaining(address who) external view returns (uint256) {
        uint256 ready = lastDrip[who] + cooldown;
        return block.timestamp >= ready ? 0 : ready - block.timestamp;
    }

    function setDrip(uint256 amount, uint256 cooldown_) external onlyOwner {
        dripAmount = amount;
        cooldown = cooldown_;
    }

    /// @notice Recover the remaining balance, e.g. when winding the faucet down.
    function sweep(address to) external onlyOwner {
        token.safeTransfer(to, token.balanceOf(address(this)));
    }
}
