# GamePredictionMarket 🎮

A next-generation prediction market smart contract designed for gaming applications, featuring constrained bonding curves that ensure mathematically sound price discovery while maintaining the fundamental constraint that option prices always sum to ≤ 1.0.

## 🎯 Overview

GamePredictionMarket allows users to create and trade on binary or multi-choice prediction questions with real money (USDC) backing. Unlike traditional AMM-based prediction markets, this implementation uses a novel constrained bonding curve mechanism that:

- **Guarantees price constraints**: Option prices can never exceed 1.0 and their sum is always ≤ 1.0
- **Ensures continuous liquidity**: Users can always buy/sell tokens, even at extreme prices
- **Provides smooth price discovery**: Prices adjust naturally based on supply and demand
- **Optimizes for gaming UX**: Fast, predictable transactions perfect for real-time gaming scenarios

## 🧮 Mathematical Foundation

### Constrained Bonding Curve Formula

```
P_i = S_i / (S_total + k)

Where:
- P_i = Price of option i
- S_i = Token supply of option i  
- S_total = Sum of all option token supplies
- k = Curve steepness parameter
```

### Key Mathematical Properties

1. **Price Constraint**: Each price approaches 1.0 asymptotically but never reaches it
2. **Sum Constraint**: Σ P_i = S_total / (S_total + k) ≤ 1.0 (mathematically guaranteed)
3. **Continuous Trading**: Always possible to buy/sell at any price level
4. **Natural Price Discovery**: More demand = higher price, with automatic deceleration

## 🚀 Features

### Core Functionality

- **Question Creation**: Owner can create prediction questions with 2-10 options
- **Token Trading**: Users buy/sell option tokens using USDC collateral
- **Automatic Resolution**: Owner resolves questions, winners split the total pool
- **House Fee**: Configurable fee (default 3%) for platform sustainability

### Advanced Features

- **Slippage Protection**: Minimum output guarantees for all trades
- **Normalized Pricing**: User-friendly probability display that sums to 100%
- **Batch Operations**: Efficient multi-option redemption
- **Emergency Controls**: Admin functions for edge cases

### Security

- **ReentrancyGuard**: Protection against reentrancy attacks
- **Input Validation**: Comprehensive parameter checking
- **Overflow Protection**: SafeMath-equivalent operations
- **Access Control**: Owner-only administrative functions

## 📋 Contract Interface

### Main Functions

```solidity
// Question Management
function createQuestion(string text, string[] options, uint256 duration, uint256 k) 
    external onlyOwner returns (uint256 questionId)

// Trading
function buyTokens(uint256 questionId, uint256 optionIndex, uint256 maxUsdcAmount, uint256 minTokensOut) 
    external returns (uint256 tokensOut, uint256 actualCost)

function sellTokens(uint256 questionId, uint256 optionIndex, uint256 tokenAmount, uint256 minUsdcOut) 
    external returns (uint256 usdcOut)

// Resolution
function resolveQuestion(uint256 questionId, uint256 winningOptionIndex) external onlyOwner

function redeemTokens(uint256 questionId, uint256 optionIndex) external
```

### View Functions

```solidity
// Pricing Information
function getPrice(uint256 questionId, uint256 optionIndex) external view returns (uint256)
function getAllPrices(uint256 questionId) external view returns (uint256[] memory)
function getNormalizedPrices(uint256 questionId) external view returns (uint256[] memory)

// Trading Calculations
function getBuyCost(uint256 questionId, uint256 optionIndex, uint256 tokenAmount) external view returns (uint256)
function getSellReturn(uint256 questionId, uint256 optionIndex, uint256 tokenAmount) external view returns (uint256)

// Question Information
function getQuestionInfo(uint256 questionId) external view returns (...)
```

## 🛠️ Deployment

### Prerequisites

- Solidity ^0.8.19
- OpenZeppelin Contracts
- USDC token contract address

### Constructor Parameters

```solidity
constructor(address _collateral)
```

- `_collateral`: Address of the USDC token contract

### Initial Setup

```solidity
// Deploy contract
GamePredictionMarket market = new GamePredictionMarket(USDC_ADDRESS);

// Create first question
uint256 questionId = market.createQuestion(
    "Will the player go to the lake?",
    ["Yes", "No"],
    600 // 10 minutes
);
```

## 💡 Usage Examples

### Basic Trading Flow

```javascript
// 1. User approves USDC spending
await usdc.approve(market.address, ethers.utils.parseUnits("100", 6));

// 2. Buy tokens for "Yes" option
await market.buyTokens(
    questionId,    // Question ID
    0,            // Option index (0 = "Yes")
    ethers.utils.parseUnits("100", 6), // Max USDC to spend
    ethers.utils.parseEther("80")      // Min tokens expected
);

// 3. Check current prices
const prices = await market.getNormalizedPrices(questionId);
console.log("Yes probability:", ethers.utils.formatEther(prices[0]));
console.log("No probability:", ethers.utils.formatEther(prices[1]));

// 4. Sell tokens before resolution
await market.sellTokens(
    questionId,
    0,
    ethers.utils.parseEther("50"), // Tokens to sell
    ethers.utils.parseUnits("45", 6) // Min USDC expected
);
```

### After Resolution

```javascript
// Owner resolves the question
await market.resolveQuestion(questionId, 0); // "Yes" wins

// Winners redeem their tokens
await market.redeemTokens(questionId, 0); // Get share of total pool
```

## 📊 Price Discovery Examples

### Scenario: Binary Question ["Yes", "No"] with k=1000

| Supply Yes | Supply No | Total Supply | Price Yes | Price No | Sum |
|------------|-----------|--------------|-----------|----------|-----|
| 0 | 0 | 0 | 0% | 0% | 0% |
| 500 | 500 | 1000 | 25% | 25% | 50% |
| 1000 | 500 | 1500 | 40% | 20% | 60% |
| 2000 | 500 | 2500 | 57% | 14% | 71% |
| 5000 | 500 | 5500 | 77% | 8% | 85% |
| 10000 | 500 | 10500 | 87% | 4% | 91% |

### Normalized Probabilities (Sum = 100%)

Using the same supplies but normalized:

| Supply Yes | Supply No | Prob Yes | Prob No |
|------------|-----------|----------|---------|
| 1000 | 500 | 66.7% | 33.3% |
| 2000 | 500 | 80% | 20% |
| 5000 | 500 | 90.9% | 9.1% |
| 10000 | 500 | 95.2% | 4.8% |

## ⚙️ Configuration

### Bonding Curve Parameter (k)

The `k` parameter controls curve steepness:

- **Higher k** (e.g., 10000): Slower price growth, more conservative market
- **Lower k** (e.g., 100): Faster price growth, more volatile market
- **Default k** = 1000: Balanced for gaming applications

### House Fee

- **Default**: 3% (300 basis points)
- **Range**: 0-10% recommended
- **Purpose**: Platform sustainability and spam prevention

## 🔒 Security Considerations

### Access Control

- **onlyOwner**: Question creation, resolution, emergency functions
- **Public**: All trading functions with proper validation

### Economic Security

- **Slippage Protection**: Users set minimum acceptable outputs
- **Constraint Enforcement**: Mathematical impossibility of invalid prices
- **Fee Structure**: Prevents dust spam while maintaining accessibility

### Technical Security

- **Reentrancy Protection**: All state-changing functions protected
- **Integer Overflow**: Solidity 0.8+ automatic checks
- **Input Validation**: Comprehensive parameter checking

## 🧪 Testing

### Unit Tests

```javascript
// Test price constraints
it("should never allow sum of prices to exceed 1.0", async () => {
    // Massive buy orders on single option
    for (let i = 0; i < 20; i++) {
        await market.buyTokens(questionId, 0, parseUnits("1000", 6), 0);
    }
    
    const prices = await market.getAllPrices(questionId);
    const sum = prices.reduce((a, b) => a.add(b));
    
    expect(sum).to.be.lte(parseEther("1.0"));
});

// Test continuous liquidity
it("should allow trading even at extreme prices", async () => {
    // Buy until price reaches ~95%
    while ((await market.getPrice(questionId, 0)).lt(parseEther("0.95"))) {
        await market.buyTokens(questionId, 0, parseUnits("100", 6), 0);
    }
    
    // Should still be able to buy more
    await expect(
        market.buyTokens(questionId, 0, parseUnits("10", 6), 0)
    ).to.not.be.reverted;
});
```

### Integration Tests

- End-to-end trading scenarios
- Multi-user market dynamics
- Resolution and redemption flows
- Edge cases and error conditions

## 📈 Gas Optimization

### Efficient Operations

- **Numerical Integration**: Optimized step sizes based on trade size
- **Batch Operations**: Single transaction for multiple redemptions
- **Storage Layout**: Packed structs for reduced storage costs

### Gas Estimates

- **Question Creation**: ~200k gas
- **Buy Tokens**: ~150-300k gas (depends on integration steps)
- **Sell Tokens**: ~120-250k gas
- **Redemption**: ~80-120k gas

## 🔮 Future Enhancements

### Potential Features

- **Automated Market Making**: Optional LP provision for bootstrapping
- **Time-weighted Pricing**: Price decay based on time to resolution
- **Multi-collateral Support**: Support for different stablecoins
- **Oracle Integration**: Automated resolution for certain question types

### Scalability

- **Layer 2 Deployment**: Optimized for Polygon, Arbitrum, etc.
- **Batch Processing**: Multi-question operations
- **Gas Subsidies**: Meta-transaction support for improved UX

## 📜 License

MIT License - see LICENSE file for details

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📞 Support

- **Documentation**: [docs.gameprediction.market](https://docs.gameprediction.market)
- **Discord**: [discord.gg/gameprediction](https://discord.gg/gameprediction)
- **Email**: support@gameprediction.market

---

**Built with ❤️ for the future of prediction markets in gaming**