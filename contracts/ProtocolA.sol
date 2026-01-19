// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProtocolA is ERC4626 {
    uint256 public constant LOCK_PERIOD = 3 minutes;

    // --- Events ---
    event RedeemRequested(uint256 indexed requestId, address indexed owner, uint256 assetsOwed, uint256 unlockTime);
    event AssetsClaimed(uint256 indexed requestId, address indexed owner, uint256 amount);

    struct Request {
        uint256 amount;
        uint256 unlockTime;
        bool processed;
    }

    mapping(uint256 => Request) public pendingWithdrawals;

    constructor(IERC20 _asset) ERC20("basicVault", "BSV") ERC4626(_asset) {}

    // STEP 1: MultiVault calls this to start the timer
    function requestRedeem(
        uint256 shares,
        uint256 requestId
    ) external returns (uint256 assetsOwed) {
        assetsOwed = previewRedeem(shares);
        
        // Burn the shares from MultiVault immediately
        _withdraw(msg.sender, address(this), msg.sender, assetsOwed, shares);

        uint256 unlockTime = block.timestamp + LOCK_PERIOD;

        pendingWithdrawals[requestId] = Request({
            amount: assetsOwed,
            unlockTime: unlockTime,
            processed: false
        });

        // Emit event to log that assets are now locked
        emit RedeemRequested(requestId, msg.sender, assetsOwed, unlockTime);
    }

    // STEP 2: MultiVault calls this after lockup period
    function claim(uint256 requestId) external {
        Request storage req = pendingWithdrawals[requestId];
        require(req.amount > 0, "Request does not exist");
        require(!req.processed, "Request already processed");
        require(block.timestamp >= req.unlockTime, "Lock period not passed");

        uint256 amount = req.amount;
        req.processed = true;

        // Emit event before transfer to follow Checks-Effects-Interactions
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