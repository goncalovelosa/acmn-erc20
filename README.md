# ACMNToken ERC-20 (Foundry + OpenZeppelin v5)

This project is a clean Foundry setup featuring a friendly, educational ERC‑20 token built on OpenZeppelin Contracts v5.x.
It is tailored for demos and workshops (e.g., ACMN — Admirável Cripto Mundo Novo) with simple, meaningful actions:

- Reward someone (mint new tokens to say “thanks” or “great job”).
- Tip friends or supporters using your balance.
- Donate to a community wallet.
- Freeze and unfreeze transfers in case of emergencies.

Contract: `src/ACMNToken.sol`

## Features

- **Standard ERC20** with customizable name, symbol, decimals
- **Burnable**: `burn`, `burnFrom`
- **Permit (EIP-2612)**: gasless approvals via `permit`
- **Pausable**: accounts with `PAUSER_ROLE` can `pause` and `unpause` transfers (emergency stop)
- **Capped supply**: cannot exceed `cap`
- **AccessControl**: role-based permissions (`MINTER_ROLE`, `PAUSER_ROLE`, `DEFAULT_ADMIN_ROLE`)
- **Examples**: `batchApprove` convenience method
- **Educational helpers**: `reward`, `airdropToClass`, `tip`, `batchTip`, `donate`, `freezeTransfers`, `unfreezeTransfers`

Comprehensive tests are provided under `test/ACMNToken.t.sol` and a deployment script at `script/DeployToken.s.sol`.

---

## ACMN Demo: Try it in 5 minutes

This walkthrough uses plain language and simple commands to show the token in action.

1. Start a local blockchain

```bash
anvil
```

1. Set environment variables (in a new terminal)

```bash
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=<anvil_private_key>
export TOKEN_NAME="ACMN Token"
export TOKEN_SYMBOL=ACMN
export TOKEN_DECIMALS=18
# Use cast to compute raw integers
export TOKEN_CAP=$(cast --to-wei 1000000 ether)
export TOKEN_INITIAL_SUPPLY=$(cast --to-wei 100000 ether)
```

1. Deploy the token

```bash
forge script script/DeployToken.s.sol:DeployTokenScript \
  --rpc-url $RPC_URL \
  --broadcast
```

1. Run the friendly demo script (optional)

```bash
export TOKEN_ADDR=<deployed_token_address>
forge script script/DemoActions.s.sol:DemoActions \
  --rpc-url $RPC_URL \
  --broadcast
```

This will set a community wallet, reward a learner, tip them, donate, and briefly pause/unpause transfers.

---

## Upgradeable (UUPS) Token

This repo also includes an upgradeable version of the token using the UUPS pattern. In short:

- Upgradeable contracts let you fix bugs or add features later without changing the token address.
- Instead of a constructor, you call `initialize(...)` once on deploy.
- A lightweight proxy (`ERC1967Proxy`) forwards calls to the implementation. Storage lives in the proxy.
- Only accounts with `DEFAULT_ADMIN_ROLE` can upgrade.

Files:

- `src/ACMNTokenUpgradeable.sol` — UUPS version of the token
- `src/ACMNTokenUpgradeableV2.sol` — example new version that adds `version()`
- `script/DeployUpgradeableToken.s.sol` — deploys proxy + implementation and runs `initialize`
- `script/UpgradeUpgradeableToken.s.sol` — upgrades a deployed proxy to V2
- `test/ACMNTokenUpgradeable.t.sol` — tests deployment, permissions, and upgrade flow

Why UUPS?

- Fewer moving parts at runtime (only a proxy, not a separate admin proxy).
- Familiar OpenZeppelin tooling and audits.

Important concepts:

- No constructors. Use `initialize(...)` and the `initializer` modifier.
- Preserve storage layout across versions. Don’t reorder or remove variables.
- Upgrades require admin authorization. We restrict upgrades to `DEFAULT_ADMIN_ROLE`.

### Deploy the upgradeable token

```bash
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=<anvil_private_key>
export TOKEN_NAME="ACMN Token"
export TOKEN_SYMBOL=ACMN
export TOKEN_DECIMALS=18
export TOKEN_CAP=$(cast --to-wei 1000000 ether)
export TOKEN_INITIAL_SUPPLY=$(cast --to-wei 100000 ether)

forge script script/DeployUpgradeableToken.s.sol:DeployUpgradeableTokenScript \
  --rpc-url $RPC_URL \
  --broadcast
```

After deployment, set your proxy address for convenience:

```bash
export PROXY_ADDR=<printed_proxy_address>
```

Interact with the proxy the same way you would a normal ERC-20:

```bash
cast call $PROXY_ADDR "name()(string)"
cast call $PROXY_ADDR "symbol()(string)"
cast call $PROXY_ADDR "decimals()(uint8)"
```

### Upgrade to V2

```bash
export PROXY_ADDR=<your_proxy_address>
forge script script/UpgradeUpgradeableToken.s.sol:UpgradeUpgradeableTokenScript \
  --rpc-url $RPC_URL \
  --broadcast
```

Confirm the new function exists (through the proxy):

```bash
cast call $PROXY_ADDR "version()(string)"
```

Notes:

- If `upgradeToAndCall` reverts, ensure your signer holds `DEFAULT_ADMIN_ROLE`.
- Don’t add constructors to upgradeable contracts; use `initialize` and `__X_init` helpers.
- Be cautious with storage layout. Add new variables after existing ones; avoid reordering.

### ERC2771 Meta-Transactions (Gasless)

The upgradeable token supports ERC-2771 meta-transactions via a trusted forwarder.

- `ERC2771ContextUpgradeable` is integrated into `src/ACMNTokenUpgradeable.sol`.
- The `trustedForwarder` can be configured at deploy-time and updated by admin later.
- Users sign messages; a relayer (forwarder) pays gas and submits the call.

Files and scripts:

- `src/ACMNTokenUpgradeable.sol` — contains `setTrustedForwarder(address)` and overrides `_msgSender()`/`_msgData()`.
- `script/DeployUpgradeableToken.s.sol` — accepts `TRUSTED_FORWARDER` to configure at deployment.
- `script/DeployForwarderAndWire.s.sol` — deploys an OpenZeppelin `ERC2771ForwarderUpgradeable` and wires it to the token.
- `test/ACMNTokenUpgradeable.t.sol` — includes tests for minimal and OpenZeppelin forwarders, domain signing, nonces, and admin gating.

#### Deploy a forwarder and wire it

```bash
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=<admin_private_key>
export PROXY_ADDR=<token_proxy_address>

forge script script/DeployForwarderAndWire.s.sol:DeployForwarderAndWire \
  --rpc-url $RPC_URL \
  --broadcast
```

This will:

- Deploy `ERC2771ForwarderUpgradeable` and initialize it with name `"ACMN Forwarder"` (EIP-712 domain name `name`).
- Call `setTrustedForwarder(forwarder)` on the token proxy.

#### Deploy token already wired to a forwarder

```bash
export TRUSTED_FORWARDER=<forwarder_address_or_0x0>
forge script script/DeployUpgradeableToken.s.sol:DeployUpgradeableTokenScript \
  --rpc-url $RPC_URL \
  --broadcast
```

#### Sign and relay an EIP-712 forward request (example with Foundry `cast` pseudocode)

Inputs:

- Domain: `name = "ACMN Forwarder"`, `version = "1"`, `chainId`, `verifyingContract = <forwarder>`
- Types: `ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)`
- Message:
  - `from = <user_address>`
  - `to = <token_proxy>`
  - `value = 0`
  - `gas = 150000` (example)
  - `nonce = <read from forwarder.nonces(user)>`
  - `deadline = <future timestamp>`
  - `data = <abi.encodeWithSelector(token.tip(address,uint256), <recipient>, <amount>)>`

Steps:

1. Compute domain separator and struct hash, then EIP-712 digest: `keccak256("\x19\x01" || domainSeparator || structHash)`.
2. Sign digest with the user’s key.
3. Build the `ForwardRequestData` struct with `signature` and submit: `forwarder.execute(request)`.

The test `testMetaTxWithOZForwarderExecute` demonstrates this flow end-to-end, including signature creation and nonce management.

Best practices:

- Use a relayer you trust (self-hosted or a reputable provider). A malicious forwarder could spoof senders.
- If rotating forwarders, update the token with `setTrustedForwarder(new)`.
- Keep upgrades admin-gated and consider a multisig for `DEFAULT_ADMIN_ROLE` in production.

## Quick Start

Prerequisites:

- Foundry installed: [Foundry Installation](https://book.getfoundry.sh/getting-started/installation)

Install deps (already vendored by this repo):

```bash
forge build
```

Run tests:

```bash
forge test -vvv
```

---

## Local Deployment (Anvil)

1. Start a local node in a new terminal:

   ```bash
   anvil
   ```

   Copy one of the printed private keys for use below.

2. Set environment variables (recommended: create a `.env` file; `.env` is already gitignored):

   ```bash
   export RPC_URL=http://127.0.0.1:8545
   export PRIVATE_KEY=<anvil_private_key>
   export TOKEN_NAME="ACMN Token"
   export TOKEN_SYMBOL=ACMN
   export TOKEN_DECIMALS=18
   # Use cast to compute raw uints for cap and initial supply
   export TOKEN_CAP=$(cast --to-wei 1000000 ether)
   export TOKEN_INITIAL_SUPPLY=$(cast --to-wei 100000 ether)
   ```

3. Deploy with Foundry script (broadcasts a transaction):

   ```bash
   forge script script/DeployToken.s.sol:DeployTokenScript \
     --rpc-url $RPC_URL \
     --broadcast
   ```

The script deploys `ACMNToken`, grants the deployer address (derived from `PRIVATE_KEY`) the `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE`, and mints the initial supply to that address.

---

## Deploy to Public Networks

Set your environment variables accordingly and provide an RPC endpoint for the target network:

```bash
export RPC_URL=<https_provider>
export PRIVATE_KEY=<your_deployer_private_key>
export TOKEN_NAME="ACMN Token"
export TOKEN_SYMBOL=ACMN
export TOKEN_DECIMALS=18
export TOKEN_CAP=$(cast --to-wei 1000000 ether)
export TOKEN_INITIAL_SUPPLY=$(cast --to-wei 100000 ether)

forge script script/DeployToken.s.sol:DeployTokenScript \
  --rpc-url $RPC_URL \
  --broadcast
```

Optional: to verify, also set `ETHERSCAN_API_KEY` and pass `--verify` if supported for your network.

---

## Interacting with the Token (cast)

Assuming `TOKEN_ADDR=0x...` is your deployed token address:

- **Read name/symbol/decimals**

  ```bash
  cast call $TOKEN_ADDR "name()(string)"
  cast call $TOKEN_ADDR "symbol()(string)"
  cast call $TOKEN_ADDR "decimals()(uint8)"
  ```

- **Mint (MINTER_ROLE only)**

  ```bash
  cast send $TOKEN_ADDR "mint(address,uint256)" <to> <amount> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  ```

- **Pause / Unpause (PAUSER_ROLE only)**

  ```bash
  cast send $TOKEN_ADDR "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  cast send $TOKEN_ADDR "unpause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  ```

- **Burn / BurnFrom**

  ```bash
  cast send $TOKEN_ADDR "burn(uint256)" 100e18 --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  cast send $TOKEN_ADDR "burnFrom(address,uint256)" <holder> 100e18 --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  ```

- **Educational helpers (friendly names)**

  ```bash
  # Set community wallet (admin only)
  cast send $TOKEN_ADDR "setCommunityWallet(address)" <community_addr> --private-key $PRIVATE_KEY --rpc-url $RPC_URL

  # Reward someone (minter only)
  cast send $TOKEN_ADDR "reward(address,uint256)" <to> 10e18 --private-key $PRIVATE_KEY --rpc-url $RPC_URL

  # Tip someone using your balance
  cast send $TOKEN_ADDR "tip(address,uint256)" <to> 2e18 --private-key $PRIVATE_KEY --rpc-url $RPC_URL

  # Donate to community wallet (requires it to be set)
  cast send $TOKEN_ADDR "donate(uint256)" 1e18 --private-key $PRIVATE_KEY --rpc-url $RPC_URL

  # Freeze / Unfreeze transfers (pauser only)
  cast send $TOKEN_ADDR "freezeTransfers()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  cast send $TOKEN_ADDR "unfreezeTransfers()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  ```

---

## Role Administration (grant, revoke, renounce)

Below are common workflows to manage roles using `cast`. The deployer initially holds `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE`.

- Get role identifiers from the contract

  ```bash
  MINTER_ROLE=$(cast call $TOKEN_ADDR "MINTER_ROLE()(bytes32)")
  PAUSER_ROLE=$(cast call $TOKEN_ADDR "PAUSER_ROLE()(bytes32)")
  ADMIN_ROLE=$(cast call $TOKEN_ADDR "DEFAULT_ADMIN_ROLE()(bytes32)")
  ```

- Grant a role (admin only)

  ```bash
  # Grants MINTER_ROLE to <address>
  cast send $TOKEN_ADDR "grantRole(bytes32,address)" $MINTER_ROLE <address> \
    --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  ```

- Verify a role

  ```bash
  cast call $TOKEN_ADDR "hasRole(bytes32,address)" $MINTER_ROLE <address>
  ```

- Revoke a role (admin only)

  ```bash
  cast send $TOKEN_ADDR "revokeRole(bytes32,address)" $MINTER_ROLE <address> \
    --private-key $PRIVATE_KEY --rpc-url $RPC_URL
  ```

- Renounce a role (must be called by the role holder themselves)

  ```bash
  # Example: <holder_pk>/<holder_addr> renounces their own MINTER_ROLE
  HOLDER_ADDR=<holder_addr>
  HOLDER_PK=<holder_pk>
  cast send $TOKEN_ADDR "renounceRole(bytes32,address)" $MINTER_ROLE $HOLDER_ADDR \
    --private-key $HOLDER_PK --rpc-url $RPC_URL
  ```

Notes:

- `renounceRole` will revert with `AccessControlBadConfirmation()` if the `address` parameter does not match `msg.sender`.
- Protect `DEFAULT_ADMIN_ROLE` carefully (ideally a multisig). Use it to grant/revoke `MINTER_ROLE` and `PAUSER_ROLE` to operational accounts.
- This token is for learning/demos. It is not money, an investment, or financial advice.

---

## Project Layout

- `src/ACMNToken.sol` – Main ERC-20 implementation with docs and example helpers
- `test/ACMNToken.t.sol` – Extensive Foundry tests for mint, burn, approvals, pause, cap, airdrops, permit
- `script/DeployToken.s.sol` – Deployment script reading parameters from env vars
- `foundry.toml` – Includes remappings for OpenZeppelin and forge-std

---

## Notes

- OpenZeppelin v5.x uses the `_update` hook for composing transfer logic (e.g., Pausable + Capped). `ACMNToken` overrides `_update` to ensure both behaviors apply.
- Decimals are configurable and returned via `decimals()` for better UI/UX alignment.
- `rescueTokens` is restricted to `DEFAULT_ADMIN_ROLE` and lets an admin recover unrelated ERC-20s accidentally sent to the token contract.

---

## Upstream Foundry Docs

For general Foundry usage, see the official docs:

[Foundry Book](https://book.getfoundry.sh/)
