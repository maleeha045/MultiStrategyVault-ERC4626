// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProtocolB is ERC4626 {
    uint256 public constant LOCK_PERIOD = 0 minutes;

    // --- Events ---
    // indexed allows you to filter logs by specific Request IDs or the MultiVault address
    event RedeemRequested(uint256 indexed requestId, address indexed caller, uint256 assetsOwed, uint256 unlockTime);
    event AssetsClaimed(uint256 indexed requestId, address indexed caller, uint256 amount);

    // Global counter to generate unique IDs
    uint256 public nextRequestId;

    struct Request {
        uint256 amount;
        uint256 unlockTime;
        bool processed;
    }

    mapping(uint256 => Request) public pendingWithdrawals;

    constructor(
        IERC20 _asset
    ) ERC20("Protocol B Vault", "PRTB") ERC4626(_asset) {}

    // STEP 1: MultiVault calls this to start the timer
    function requestRedeem(
        uint256 shares,
        uint256 _requestId
    ) external returns (uint256 assetsOwed) {
        assetsOwed = previewRedeem(shares);
        
        // Burn the shares from MultiVault immediately
        _withdraw(msg.sender, address(this), msg.sender, assetsOwed, shares);

        uint256 unlockTime = block.timestamp + LOCK_PERIOD;

        pendingWithdrawals[_requestId] = Request({
            amount: assetsOwed,
            unlockTime: unlockTime,
            processed: false
        });

        // Emit the request event
        emit RedeemRequested(_requestId, msg.sender, assetsOwed, unlockTime);
    }

    // STEP 2: MultiVault calls this
    function claim(uint256 requestId) external {
        Request storage req = pendingWithdrawals[requestId];
        require(req.amount > 0, "Request does not exist");
        require(!req.processed, "Request already processed");
        require(block.timestamp >= req.unlockTime, "Lock period not passed");

        uint256 amount = req.amount;
        req.processed = true;

        // Emit the claim event before the transfer (following CEI pattern)
        emit AssetsClaimed(requestId, msg.sender, amount);

        IERC20(asset()).transfer(msg.sender, amount);
    }

    function getPendingWithdrawalsAmount(
        uint256 requestId
    ) external view returns (uint256) {
        return pendingWithdrawals[requestId].amount;
    }

    function isRequestProcessed(
        uint256 requestId
    ) external view returns (bool) {
        return pendingWithdrawals[requestId].processed;
    }
}