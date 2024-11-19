// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title GybernatyUnitManager
 * @dev Contract for managing user levels and token withdrawals in the Gybernaty system
 */
contract GybernatyUnitManager is ReentrancyGuard, Pausable, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant GYBERNATY_ROLE = keccak256("GYBERNATY_ROLE");
    
    struct User {
        address userAddress;
        string name;
        string link;
        bool markedUp;
        bool markedDown;
        uint32 level;
        uint256 lastWithdrawTime;
        uint256 withdrawCount;
        bool exists;
    }

    // Constants
    uint32 public constant MAX_LEVEL = 4;
    uint32 public constant MIN_LEVEL = 1;
    uint256 public constant GBR_TOKEN_AMOUNT = 1_000_000_000_000;
    uint256 public constant BNB_AMOUNT = 1000 ether;
    uint256 public constant MAX_MONTHLY_WITHDRAWALS = 2;
    uint256 public constant MONTH_IN_SECONDS = 30 days;

    // State variables
    IERC20 public immutable gbrToken;
    mapping(address => User) public users;
    mapping(uint32 => uint256) public levelWithdrawLimits;
    
    // Events
    event UserMarkedUp(address indexed userAddress, uint32 currentLevel);
    event UserMarkedDown(address indexed userAddress, uint32 currentLevel);
    event UserLevelChanged(address indexed userAddress, uint32 oldLevel, uint32 newLevel);
    event GybernatyJoined(address indexed gybernatyAddress, uint256 amount);
    event TokensWithdrawn(address indexed userAddress, uint256 amount);
    event UserCreated(address indexed userAddress, string name, uint32 level);

    // Custom errors
    error InvalidLevel(uint32 level);
    error UserAlreadyExists(address userAddress);
    error UserDoesNotExist(address userAddress);
    error NotMarkedForChange(address userAddress);
    error LevelLimitReached(uint32 currentLevel);
    error InsufficientPayment(uint256 provided, uint256 required);
    error WithdrawalLimitExceeded(uint256 currentCount, uint256 maxCount);
    error InsufficientWithdrawalBalance(uint256 requested, uint256 available);
    error InvalidWithdrawalAmount();

    /**
     * @dev Constructor initializes the contract with initial withdrawal limits and GBR token
     * @param _gbrTokenAddress Address of the GBR token contract
     */
    constructor(address _gbrTokenAddress) {
        require(_gbrTokenAddress != address(0), "Invalid token address");
        
        gbrToken = IERC20(_gbrTokenAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize withdrawal limits for each level
        levelWithdrawLimits[1] = 1_000_000_000_000;
        levelWithdrawLimits[2] = 10_000_000_000_000;
        levelWithdrawLimits[3] = 100_000_000_000_000;
        levelWithdrawLimits[4] = 1_000_000_000_000_000;
    }

    /**
     * @dev Allows users to join as Gybernaty by providing sufficient tokens or BNB
     */
    function joinGybernaty() external payable whenNotPaused {
        bool hasGbrTokens = gbrToken.balanceOf(msg.sender) >= GBR_TOKEN_AMOUNT;
        bool hasBnb = msg.value >= BNB_AMOUNT;
        
        if (!hasGbrTokens && !hasBnb) {
            revert InsufficientPayment(
                hasGbrTokens ? msg.value : gbrToken.balanceOf(msg.sender),
                hasGbrTokens ? BNB_AMOUNT : GBR_TOKEN_AMOUNT
            );
        }

        _grantRole(GYBERNATY_ROLE, msg.sender);
        
        emit GybernatyJoined(msg.sender, hasGbrTokens ? GBR_TOKEN_AMOUNT : msg.value);
    }

    /**
     * @dev Creates a new user with specified parameters
     */
    function createUser(
        address userAddress,
        uint32 level,
        string calldata name,
        string calldata link
    ) external onlyRole(GYBERNATY_ROLE) whenNotPaused {
        if (users[userAddress].exists) {
            revert UserAlreadyExists(userAddress);
        }
        if (level < MIN_LEVEL || level > MAX_LEVEL) {
            revert InvalidLevel(level);
        }

        users[userAddress] = User({
            userAddress: userAddress,
            name: name,
            link: link,
            markedUp: false,
            markedDown: false,
            level: level,
            lastWithdrawTime: 0,
            withdrawCount: 0,
            exists: true
        });

        emit UserCreated(userAddress, name, level);
    }

    /**
     * @dev Marks a user for level up
     */
    function markForLevelUp() external whenNotPaused {
        User storage user = users[msg.sender];
        if (!user.exists) {
            revert UserDoesNotExist(msg.sender);
        }
        if (user.level >= MAX_LEVEL) {
            revert LevelLimitReached(user.level);
        }

        user.markedUp = true;
        user.markedDown = false;
        
        emit UserMarkedUp(msg.sender, user.level);
    }

    /**
     * @dev Marks a user for level down
     */
    function markForLevelDown(address userAddress) 
        external 
        onlyRole(GYBERNATY_ROLE) 
        whenNotPaused 
    {
        User storage user = users[userAddress];
        if (!user.exists) {
            revert UserDoesNotExist(userAddress);
        }
        if (user.level <= MIN_LEVEL) {
            revert LevelLimitReached(user.level);
        }

        user.markedDown = true;
        user.markedUp = false;
        
        emit UserMarkedDown(userAddress, user.level);
    }

    /**
     * @dev Executes level change for a user
     */
    function executeUserLevelChange(address userAddress, bool isLevelUp) 
        external 
        onlyRole(GYBERNATY_ROLE) 
        whenNotPaused 
    {
        User storage user = users[userAddress];
        if (!user.exists) {
            revert UserDoesNotExist(userAddress);
        }
        
        bool isMarked = isLevelUp ? user.markedUp : user.markedDown;
        if (!isMarked) {
            revert NotMarkedForChange(userAddress);
        }

        uint32 oldLevel = user.level;
        uint32 newLevel = isLevelUp ? user.level + 1 : user.level - 1;
        
        if (newLevel < MIN_LEVEL || newLevel > MAX_LEVEL) {
            revert InvalidLevel(newLevel);
        }

        user.level = newLevel;
        user.markedUp = false;
        user.markedDown = false;
        
        emit UserLevelChanged(userAddress, oldLevel, newLevel);
    }

    /**
     * @dev Allows users to withdraw tokens based on their level
     */
    function withdrawTokens(uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        User storage user = users[msg.sender];
        if (!user.exists) {
            revert UserDoesNotExist(msg.sender);
        }
        if (amount == 0) {
            revert InvalidWithdrawalAmount();
        }

        uint256 maxAmount = levelWithdrawLimits[user.level];
        if (amount > maxAmount) {
            revert InsufficientWithdrawalBalance(amount, maxAmount);
        }

        uint256 currentMonth = block.timestamp / MONTH_IN_SECONDS;
        uint256 lastWithdrawMonth = user.lastWithdrawTime / MONTH_IN_SECONDS;

        if (currentMonth == lastWithdrawMonth && user.withdrawCount >= MAX_MONTHLY_WITHDRAWALS) {
            revert WithdrawalLimitExceeded(user.withdrawCount, MAX_MONTHLY_WITHDRAWALS);
        }

        if (currentMonth > lastWithdrawMonth) {
            user.withdrawCount = 0;
        }

        user.withdrawCount++;
        user.lastWithdrawTime = block.timestamp;

        require(gbrToken.transfer(msg.sender, amount), "Token transfer failed");
        
        emit TokensWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause function
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Allows contract to receive BNB
     */
    receive() external payable {}
}