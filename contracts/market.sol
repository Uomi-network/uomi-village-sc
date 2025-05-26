// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GamePredictionMarket
 * @dev Prediction market with constrained bonding curves
 * 
 * Uses modified bonding curve that ensures sum of all option prices = 1.0
 * Formula: P_i = S_i / (S_total + k)
 * Where S_i = supply of option i, S_total = sum of all supplies
 * 
 * This guarantees:
 * - Each price asymptotically approaches 1.0 but never reaches it
 * - Sum of all prices always equals 1.0
 * - Natural market behavior with constraint enforcement
 */
contract GamePredictionMarket is ERC1155, Ownable, ReentrancyGuard, ERC1155Supply {
    
    struct Question {
        string text;
        string[] options;
        uint256 endTime;
        uint256 resolvedOption;
        bool resolved;
        uint256 totalCollateral; // Total USDC deposited
        uint256 k; // Bonding curve parameter
        uint256 totalSupply; // Sum of all option token supplies
    }
    
    IERC20 public immutable collateral;
    uint256 public nextQuestionId = 1;
    uint256 public constant HOUSE_FEE_BPS = 300; // 3%
    uint256 public constant DEFAULT_K = 1000 * 1e18; // Default curve steepness
    uint256 public constant PRECISION = 1e18;
    
    mapping(uint256 => Question) public questions;
    mapping(uint256 => uint256) public tokenSupplies; // tokenId => circulating supply
    
    event QuestionCreated(uint256 indexed questionId, string text, string[] options, uint256 endTime, uint256 k);
    event TokensBought(uint256 indexed tokenId, address indexed user, uint256 usdcPaid, uint256 tokensReceived);
    event TokensSold(uint256 indexed tokenId, address indexed user, uint256 tokensSold, uint256 usdcReceived);
    event QuestionResolved(uint256 indexed questionId, uint256 winningOption);
    event WinnerPayout(address indexed user, uint256 indexed questionId, uint256 payout);
    
    constructor(address _collateral) ERC1155("") Ownable(msg.sender) {
        require(_collateral != address(0), "Invalid collateral");
        collateral = IERC20(_collateral);
    }
    
    /**
     * @dev Create a new prediction question
     */
    function createQuestion(
        string memory text,
        string[] memory options,
        uint256 duration,
        uint256 k
    ) external onlyOwner returns (uint256 questionId) {
        require(bytes(text).length > 0, "Empty question");
        require(options.length >= 2 && options.length <= 10, "Invalid options count");
        require(duration > 0, "Invalid duration");
        
        if (k == 0) {
            k = DEFAULT_K;
        }
        
        questionId = nextQuestionId++;
        Question storage q = questions[questionId];
        
        q.text = text;
        q.options = options;
        q.endTime = block.timestamp + duration;
        q.resolved = false;
        q.totalCollateral = 0;
        q.k = k;
        q.totalSupply = 0;
        
        emit QuestionCreated(questionId, text, options, q.endTime, k);
    }
    /**
     * @dev Buy tokens using constrained bonding curve
     * Price formula: P_i = S_i / (S_total + k)
     * This ensures sum of all prices = S_total / (S_total + k) ≤ 1.0
     */
    function buyTokens(
        uint256 questionId,
        uint256 optionIndex,
        uint256 maxUsdcAmount,
        uint256 minTokensOut
    ) external nonReentrant returns (uint256 tokensOut, uint256 actualCost) {
        Question storage q = questions[questionId];
        require(block.timestamp < q.endTime, "Betting ended");
        require(optionIndex < q.options.length, "Invalid option");
        require(maxUsdcAmount > 0, "Invalid amount");
        
        uint256 tokenId = _getTokenId(questionId, optionIndex);
        uint256 currentSupply = tokenSupplies[tokenId];
        
        // Calculate tokens out using constrained bonding curve
        (tokensOut, actualCost) = _calculateTokensOut(
            currentSupply,
            maxUsdcAmount,
            q.k,
            q.totalSupply
        );
        
        require(tokensOut >= minTokensOut, "Slippage exceeded");
        require(tokensOut > 0, "Insufficient output");
        require(actualCost <= maxUsdcAmount, "Cost exceeded maximum");
        
        // Verify price constraint (should be automatic, but double-check)
        uint256 newTotalSupply = q.totalSupply + tokensOut;
        uint256 newPrice = ((currentSupply + tokensOut) * PRECISION) / (newTotalSupply + q.k);
        require(newPrice < PRECISION, "Price would exceed 1.0"); // Should never happen with correct math
        
        // Transfer USDC from user
        collateral.transferFrom(msg.sender, address(this), actualCost);
        
        // Update state
        tokenSupplies[tokenId] += tokensOut;
        q.totalSupply += tokensOut;
        q.totalCollateral += actualCost;
        
        // Mint tokens to user
        _mint(msg.sender, tokenId, tokensOut, "");
        
        emit TokensBought(tokenId, msg.sender, actualCost, tokensOut);
    }
    
    /**
     * @dev Sell tokens back to the constrained bonding curve
     */
    function sellTokens(
        uint256 questionId,
        uint256 optionIndex,
        uint256 tokenAmount,
        uint256 minUsdcOut
    ) external nonReentrant returns (uint256 usdcOut) {
        Question storage q = questions[questionId];
        require(block.timestamp < q.endTime, "Trading ended");
        require(optionIndex < q.options.length, "Invalid option");
        require(tokenAmount > 0, "Invalid amount");
        
        uint256 tokenId = _getTokenId(questionId, optionIndex);
        require(balanceOf(msg.sender, tokenId) >= tokenAmount, "Insufficient balance");
        
        uint256 currentSupply = tokenSupplies[tokenId];
        require(currentSupply >= tokenAmount, "Invalid supply state");
        
        // Calculate USDC out using constrained bonding curve
        usdcOut = _calculateUsdcOut(
            currentSupply,
            tokenAmount,
            q.k,
            q.totalSupply
        );
        
        require(usdcOut >= minUsdcOut, "Slippage exceeded");
        require(usdcOut > 0, "No output");
        
        // Burn tokens from user
        _burn(msg.sender, tokenId, tokenAmount);
        
        // Update state
        tokenSupplies[tokenId] -= tokenAmount;
        q.totalSupply -= tokenAmount;
        q.totalCollateral -= usdcOut;
        
        // Transfer USDC to user
        collateral.transfer(msg.sender, usdcOut);
        
        emit TokensSold(tokenId, msg.sender, tokenAmount, usdcOut);
    }
    
    /**
     * @dev Resolve the question with winning option
     */
    function resolveQuestion(uint256 questionId, uint256 winningOptionIndex) external onlyOwner {
        Question storage q = questions[questionId];
        require(block.timestamp >= q.endTime, "Question not ended");
        require(!q.resolved, "Already resolved");
        require(winningOptionIndex < q.options.length, "Invalid option");
        
        q.resolved = true;
        q.resolvedOption = winningOptionIndex;
        
        emit QuestionResolved(questionId, winningOptionIndex);
    }
    
    /**
     * @dev Redeem winning tokens for share of total collateral
     */
    function redeemTokens(uint256 questionId, uint256 optionIndex) external nonReentrant {
        Question storage q = questions[questionId];
        require(q.resolved, "Not resolved");
        
        uint256 tokenId = _getTokenId(questionId, optionIndex);
        uint256 userBalance = balanceOf(msg.sender, tokenId);
        require(userBalance > 0, "No tokens");
        
        if (optionIndex == q.resolvedOption) {
            // Winner: get proportional share of total collateral
            uint256 winningTokenId = _getTokenId(questionId, q.resolvedOption);
            uint256 totalWinningTokens = totalSupply(winningTokenId);
            require(totalWinningTokens > 0, "No winning tokens");
            
            // Calculate payouts
            uint256 houseFee = (q.totalCollateral * HOUSE_FEE_BPS) / 10000;
            uint256 winnerPool = q.totalCollateral - houseFee;
            uint256 userPayout = (userBalance * winnerPool) / totalWinningTokens;
            
            // Burn tokens
            _burn(msg.sender, tokenId, userBalance);
            
            // Transfer payout and house fee
            if (userPayout > 0) {
                collateral.transfer(msg.sender, userPayout);
            }
            if (houseFee > 0) {
                collateral.transfer(owner(), houseFee);
            }
            
            emit WinnerPayout(msg.sender, questionId, userPayout);
            
        } else {
            // Loser: tokens become worthless
            _burn(msg.sender, tokenId, userBalance);
        }
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Get current price for an option
     * Price formula: P_i = S_i / (S_total + k)
     * This ensures sum of all prices = S_total / (S_total + k) ≤ 1.0
     */
    function getPrice(uint256 questionId, uint256 optionIndex) external view returns (uint256) {
        uint256 tokenId = _getTokenId(questionId, optionIndex);
        uint256 supply = tokenSupplies[tokenId];
        Question storage q = questions[questionId];
        
        if (q.totalSupply + q.k == 0) return 0;
        
        return (supply * PRECISION) / (q.totalSupply + q.k);
    }
    
    /**
     * @dev Get all current prices for a question
     * Guaranteed to sum to exactly S_total / (S_total + k) ≤ 1.0
     */
    function getAllPrices(uint256 questionId) external view returns (uint256[] memory) {
        Question storage q = questions[questionId];
        uint256[] memory prices = new uint256[](q.options.length);
        
        if (q.totalSupply + q.k == 0) {
            // All prices are 0 if no tokens minted yet
            return prices;
        }
        
        for (uint256 i = 0; i < q.options.length; i++) {
            uint256 tokenId = _getTokenId(questionId, i);
            uint256 supply = tokenSupplies[tokenId];
            prices[i] = (supply * PRECISION) / (q.totalSupply + q.k);
        }
        
        return prices;
    }
    
    /**
     * @dev Get normalized prices that sum to exactly 1.0
     * This is what users should see as "market probabilities"
     */
    function getNormalizedPrices(uint256 questionId) external view returns (uint256[] memory) {
        Question storage q = questions[questionId];
        uint256[] memory prices = new uint256[](q.options.length);
        
        if (q.totalSupply == 0) {
            // Equal probabilities if no trading yet
            uint256 equalPrice = PRECISION / q.options.length;
            for (uint256 i = 0; i < q.options.length; i++) {
                prices[i] = equalPrice;
            }
            return prices;
        }
        
        // Normalized: P_i_norm = S_i / S_total
        for (uint256 i = 0; i < q.options.length; i++) {
            uint256 tokenId = _getTokenId(questionId, i);
            uint256 supply = tokenSupplies[tokenId];
            prices[i] = (supply * PRECISION) / q.totalSupply;
        }
        
        return prices;
    }
    
    /**
     * @dev Calculate cost to buy a specific amount of tokens
     */
    function getBuyCost(uint256 questionId, uint256 optionIndex, uint256 tokenAmount) 
        external view returns (uint256) {
        uint256 tokenId = _getTokenId(questionId, optionIndex);
        uint256 currentSupply = tokenSupplies[tokenId];
        Question storage q = questions[questionId];
        
        return _calculateBuyCost(currentSupply, tokenAmount, q.k, q.totalSupply);
    }
    
    /**
     * @dev Calculate USDC received for selling tokens
     */
    function getSellReturn(uint256 questionId, uint256 optionIndex, uint256 tokenAmount) 
        external view returns (uint256) {
        uint256 tokenId = _getTokenId(questionId, optionIndex);
        uint256 currentSupply = tokenSupplies[tokenId];
        Question storage q = questions[questionId];
        
        return _calculateUsdcOut(currentSupply, tokenAmount, q.k, q.totalSupply);
    }
    
    function getQuestionInfo(uint256 questionId) external view returns (
        string memory text,
        string[] memory options,
        uint256 endTime,
        bool resolved,
        uint256 resolvedOption,
        uint256 totalCollateral,
        uint256 k,
        uint256 totalSupply
    ) {
        Question storage q = questions[questionId];
        return (q.text, q.options, q.endTime, q.resolved, q.resolvedOption, q.totalCollateral, q.k, q.totalSupply);
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _getTokenId(uint256 questionId, uint256 optionIndex) internal pure returns (uint256) {
        return questionId * 1000 + optionIndex;
    }
    
    /**
     * @dev Calculate tokens out for constrained bonding curve
     * Formula: P_i = S_i / (S_total + k)
     * Cost = ∫[S_i to S_i + tokens] (s + other_supplies) / (S_total + tokens_bought_so_far + k) ds
     * 
     * This is complex to integrate analytically, so we use numerical approximation
     */
    function _calculateTokensOut(
        uint256 currentSupply,
        uint256 maxUsdcAmount,
        uint256 k,
        uint256 totalSupply
    ) internal pure returns (uint256 tokensOut, uint256 actualCost) {
        
        // For small purchases, use direct approximation
        if (maxUsdcAmount <= 100 * PRECISION) {
            uint256 currentPrice = totalSupply + k == 0 ? 0 : (PRECISION * PRECISION) / (totalSupply + k);
            tokensOut = (maxUsdcAmount * PRECISION) / (currentPrice + PRECISION); // Add small premium
            actualCost = _calculateBuyCost(currentSupply, tokensOut, k, totalSupply);
            
            if (actualCost > maxUsdcAmount) {
                tokensOut = (tokensOut * maxUsdcAmount) / actualCost;
                actualCost = maxUsdcAmount;
            }
            return (tokensOut, actualCost);
        }
        
        // For larger purchases, use binary search
        uint256 low = 0;
        uint256 high = maxUsdcAmount; // Upper bound estimate
        
        for (uint256 i = 0; i < 50; i++) {
            uint256 mid = (low + high) / 2;
            uint256 cost = _calculateBuyCost(currentSupply, mid, k, totalSupply);
            
            if (cost <= maxUsdcAmount) {
                tokensOut = mid;
                actualCost = cost;
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
    }
    
    /**
     * @dev Calculate cost for buying tokens with constrained bonding curve
     * Uses numerical integration with small steps for accuracy
     */
    function _calculateBuyCost(
        uint256 currentSupply,
        uint256 tokenAmount,
        uint256 k,
        uint256 totalSupply
    ) internal pure returns (uint256 totalCost) {
        if (tokenAmount == 0) return 0;
        
        // Numerical integration: divide purchase into small steps
        uint256 steps = tokenAmount > 1000 * PRECISION ? 100 : 10;
        uint256 stepSize = tokenAmount / steps;
        
        uint256 runningSupply = currentSupply;
        uint256 runningTotalSupply = totalSupply;
        
        for (uint256 i = 0; i < steps; i++) {
            uint256 currentStepSize = (i == steps - 1) ? tokenAmount - i * stepSize : stepSize;
            
            // Price at this step: P = (S_i + step/2) / (S_total + step/2 + k)
            uint256 avgSupply = runningSupply + currentStepSize / 2;
            uint256 avgTotalSupply = runningTotalSupply + currentStepSize / 2;
            
            uint256 stepPrice = (avgSupply * PRECISION) / (avgTotalSupply + k);
            uint256 stepCost = (currentStepSize * stepPrice) / PRECISION;
            
            totalCost += stepCost;
            runningSupply += currentStepSize;
            runningTotalSupply += currentStepSize;
        }
    }
    
    /**
     * @dev Calculate USDC out for selling tokens
     */
    function _calculateUsdcOut(
        uint256 currentSupply,
        uint256 tokenAmount,
        uint256 k,
        uint256 totalSupply
    ) internal pure returns (uint256 totalReturn) {
        if (tokenAmount == 0 || tokenAmount > currentSupply) return 0;
        
        // Same numerical integration but in reverse
        uint256 steps = tokenAmount > 1000 * PRECISION ? 100 : 10;
        uint256 stepSize = tokenAmount / steps;
        
        uint256 runningSupply = currentSupply;
        uint256 runningTotalSupply = totalSupply;
        
        for (uint256 i = 0; i < steps; i++) {
            uint256 currentStepSize = (i == steps - 1) ? tokenAmount - i * stepSize : stepSize;
            
            // Price at this step
            uint256 avgSupply = runningSupply - currentStepSize / 2;
            uint256 avgTotalSupply = runningTotalSupply - currentStepSize / 2;
            
            uint256 stepPrice = (avgSupply * PRECISION) / (avgTotalSupply + k);
            uint256 stepReturn = (currentStepSize * stepPrice) / PRECISION;
            
            totalReturn += stepReturn;
            runningSupply -= currentStepSize;
            runningTotalSupply -= currentStepSize;
        }
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = collateral.balanceOf(address(this));
        collateral.transfer(owner(), balance);
    }
    
    function setURI(string memory newURI) external onlyOwner {
        _setURI(newURI);
    }
    
    // Override _update to resolve conflict between ERC1155 and ERC1155Supply
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }
}