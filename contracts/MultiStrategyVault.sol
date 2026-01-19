// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface Ierc4626 {
    function requestRedeem(uint256 shares, uint256 requestId) external returns (uint256);
    function claim(uint256 requestId) external;
    function isRequestProcessed(uint256 requestId) external view returns(bool);
    function getPendingWithdrawalsAmount(uint256 requestId) external view returns(uint256);
}

contract MultiStrategyVault is ERC4626, AccessControl, Pausable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    
    // --- Events ---
    event AllocationsUpdated(Allocation[] newAllocations);
    event Rebalanced(uint256 totalAssets);
    event WithdrawalRequested(uint256 indexed requestId, address indexed user, uint256 shares, uint256 amountExpected);
    event WithdrawalClaimed(uint256 indexed requestId, address indexed user, uint256 amountClaimed);
    event ProtocolClaimFailed(uint256 indexed requestId, address protocol);

    struct Allocation {
        address protocol;
        uint256 targetBps; 
    }

    struct WithdrawalRequest {
        address user;
        uint256 shares;
        uint256 amountExpected;
        uint256 amountProcessed;
    }

    Allocation[] public allocations;
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    mapping(address => uint256[]) public userRequestIds;
    
    uint256 public nextRequestId;
    uint256 public constant MAX_BPS = 10000;
    uint256 public constant ALLOCATION_CAP = 5000;

    constructor(IERC20 _asset, address managerRole, string memory _name, string memory _symbol) 
        ERC4626(_asset) 
        ERC20(_name, _symbol) 
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, managerRole);
    }

    // --- Multi-Protocol Routing ---

    function totalAssets() public view override returns (uint256) {
        uint256 total = IERC20(asset()).balanceOf(address(this));
        for (uint i = 0; i < allocations.length; i++) {
            total += IERC4626(allocations[i].protocol).totalAssets();
        }
        return total;
    }

    function setAllocations(Allocation[] calldata _allocations) external onlyRole(MANAGER_ROLE) {
        uint256 totalBps = 0;
        for (uint i = 0; i < _allocations.length; i++) {
          //  require(_allocations[i].targetBps <= ALLOCATION_CAP, "Exceeds 50% cap");
            totalBps += _allocations[i].targetBps;
        }
        require(totalBps <= MAX_BPS, "Total > 100%");
        
        delete allocations;
        for (uint i = 0; i < _allocations.length; i++) {
            allocations.push(_allocations[i]);
        }
        emit AllocationsUpdated(_allocations);
    }

    function rebalance() external onlyRole(MANAGER_ROLE) whenNotPaused {
        uint256 total = totalAssets();
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));

        for (uint i = 0; i < allocations.length; i++) {
            uint256 target = (total * allocations[i].targetBps) / MAX_BPS;
            uint256 current = IERC4626(allocations[i].protocol).totalAssets();

            if (target > current) {
                uint256 diff = target - current;
                if (diff > vaultBalance) diff = vaultBalance; 
                
                if (diff > 0) {
                    IERC20(asset()).approve(allocations[i].protocol, diff);
                    IERC4626(allocations[i].protocol).deposit(diff, address(this));
                    vaultBalance -= diff;
                }
            }
        }
        emit Rebalanced(total);
    }

    // --- Withdrawal Queue ---

    function requestWithdraw(uint256 shares) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        uint256 assets = previewRedeem(shares);

        userRequestIds[msg.sender].push(requestId);
        
        uint256 currentTotalSupply = totalSupply();

        for (uint i = 0; i < allocations.length; i++) {
            uint256 underlyingSharesToBurn = (IERC20(allocations[i].protocol).balanceOf(address(this)) * shares) / currentTotalSupply;
            if (underlyingSharesToBurn > 0) {
                Ierc4626(allocations[i].protocol).requestRedeem(underlyingSharesToBurn, requestId);
            }
        }

        _burn(msg.sender, shares);
        
        withdrawalRequests[requestId] = WithdrawalRequest({
            user: msg.sender,
            shares: shares,
            amountExpected: assets,
            amountProcessed: 0
        });

        emit WithdrawalRequested(requestId, msg.sender, shares, assets);
    }

    function claimWithdraw(uint256 requestId) external {
        WithdrawalRequest storage req = withdrawalRequests[requestId];
        require(req.user == msg.sender, "Not your request");
        require(req.amountExpected > req.amountProcessed, "Nothing left to claim");

        uint256 totalClaimedInThisSession = 0;

        for (uint i = 0; i < allocations.length; i++) {
            address protocolAddr = allocations[i].protocol;

            try Ierc4626(protocolAddr).claim(requestId) {
                if (Ierc4626(protocolAddr).isRequestProcessed(requestId)) {
                    uint256 amount = Ierc4626(protocolAddr).getPendingWithdrawalsAmount(requestId);
                    totalClaimedInThisSession += amount;
                }
            } catch {
                emit ProtocolClaimFailed(requestId, protocolAddr);
                continue;
            }
        }

        if (totalClaimedInThisSession > 0) {
            req.amountProcessed += totalClaimedInThisSession;
            IERC20(asset()).transfer(msg.sender, totalClaimedInThisSession);
            emit WithdrawalClaimed(requestId, msg.sender, totalClaimedInThisSession);
        }
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }
}