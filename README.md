# MultiProtocol-ERC4626 Vault

This project demonstrates how vaults manage liquidity, protocol risk, and user withdrawals in production-grade DeFi systems.

Key Points: 

ERC-4626 compliant vault (USDC deposits → vault shares)

Capital allocation across multiple protocols with configurable weights

Rebalancing logic to route idle liquidity

Withdrawal queue handling for protocol lockups

Role-based access control & safety mechanisms

End-to-end testing with mock protocols

```Testnet
MultiStrategyVault: https://sepolia.etherscan.io/address/0xea694a96772ea0a630a093d7ba05a13b0d0d2fe3#code
Protocol A: https://sepolia.etherscan.io/address/0x1c12d57f3b99df2a29794f7e784dbc2b648c1c03#code
Protocol B: https://sepolia.etherscan.io/address/0xd428a661ccac0c78f8bd563934ef2d1bb1039c7a#code
Mock USDC: https://sepolia.etherscan.io/address/0x3c27eadc087025ea52659aa2d834e82ba64f07b4#code
```
Built using Solidity, OpenZeppelin, Hardhat, and ERC-4626 standards.
