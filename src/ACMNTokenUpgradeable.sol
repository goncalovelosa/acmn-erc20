// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// OpenZeppelin Upgradeable Imports (v5.1.0)
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20CappedUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ERC2771ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/metatx/ERC2771ContextUpgradeable.sol";
import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";

// Non-upgradeable helper
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ACMNTokenUpgradeable (UUPS)
 * @notice Upgradeable version of ACMNToken using UUPS proxies. Designed for education:
 *         initialize instead of constructor, upgrade with Upgrade script, state preserved.
 */
contract ACMNTokenUpgradeable is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PermitUpgradeable,
    ERC20PausableUpgradeable,
    ERC20CappedUpgradeable,
    AccessControlUpgradeable,
    ERC2771ContextUpgradeable,
    UUPSUpgradeable
{
    /// @notice Role that allows minting new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Role that allows pausing and unpausing transfers.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Token decimals value (ERC20 default is 18). Stored and returned by `decimals()`.
    uint8 private _tokenDecimals;

    /// @notice Optional community wallet for donations (set by admin).
    address public communityWallet;

    /// @dev Trusted ERC-2771 forwarder for gasless meta-txs (configurable).
    address private _trustedForwarder;

    /// @notice Emitted when a learner/supporter is rewarded (minted tokens).
    event LearnerRewarded(address indexed to, uint256 amount);
    /// @notice Emitted when someone tips another user (transfer).
    event Tipped(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted on each recipient in a batch tip.
    event BatchTipped(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when someone donates to the community wallet.
    event Donated(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when the community wallet is updated by an admin.
    event CommunityWalletUpdated(address indexed previous, address indexed current);
    /// @notice Emitted when unrelated tokens are rescued by an admin.
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when the trusted forwarder is updated by an admin.
    event TrustedForwarderUpdated(address indexed previous, address indexed current);

    /// @dev Revert on receiving native ETH to prevent accidental sends.
    error ETHNotAccepted();
    /// @dev Shared error for array length mismatches in batch operations.
    error LengthMismatch();
    /// @dev Community wallet cannot be zero address.
    error CommunityZeroAddress();
    /// @dev Community wallet not configured.
    error CommunityNotSet();
    /// @dev Cannot rescue this token itself.
    error RescueSelf();
    /// @dev Recipient cannot be zero address.
    error RescueZeroRecipient();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 cap_,
        uint256 initialSupply,
        address initialAdmin,
        address trustedForwarder_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC20Pausable_init();
        __ERC20Capped_init(cap_);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _tokenDecimals = decimals_;
        // aderyn-ignore-next-line(state-no-address-check)
        _trustedForwarder = trustedForwarder_;
        emit TrustedForwarderUpdated(address(0), trustedForwarder_);

        // Roles: initial admin also receives MINTER and PAUSER roles.
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MINTER_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);

        if (initialSupply > 0) {
            _mint(initialAdmin, initialSupply);
        }
    }

    // ======== Role-Gated Admin Functions ========

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function freezeTransfers() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unfreezeTransfers() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function airdropMint(address[] calldata recipients, uint256[] calldata amounts) external onlyRole(MINTER_ROLE) {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        // SSTORE inside _mint is inherent to per-recipient distribution; loop is micro-optimized.
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i = 0; i < len; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            if (amt != 0) {
                _mint(to, amt);
            }
            unchecked { ++i; }
        }
    }

    function airdropToClass(address[] calldata recipients, uint256[] calldata amounts) external onlyRole(MINTER_ROLE) {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i = 0; i < len; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            if (amt != 0) {
                _mint(to, amt);
            }
            unchecked { ++i; }
        }
    }

    function reward(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit LearnerRewarded(to, amount);
    }

    // ======== User Convenience Functions ========

    function airdropTransfer(address[] calldata recipients, uint256[] calldata amounts) external {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i = 0; i < len; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            if (amt != 0) {
                transfer(to, amt);
            }
            unchecked { ++i; }
        }
    }

    function batchApprove(address[] calldata spenders, uint256 amount) external {
        uint256 len = spenders.length;
        for (uint256 i = 0; i < len; i++) {
            _approve(_msgSender(), spenders[i], amount);
        }
    }

    function tip(address to, uint256 amount) external {
        transfer(to, amount);
        emit Tipped(_msgSender(), to, amount);
    }

    function batchTip(address[] calldata recipients, uint256[] calldata amounts) external {
        uint256 len = recipients.length;
        if (len != amounts.length) revert LengthMismatch();
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i = 0; i < len; ) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            if (amt != 0) {
                transfer(to, amt);
                emit BatchTipped(_msgSender(), to, amt);
            }
            unchecked { ++i; }
        }
    }

    function setCommunityWallet(address newWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newWallet == address(0)) revert CommunityZeroAddress();
        emit CommunityWalletUpdated(communityWallet, newWallet);
        communityWallet = newWallet;
    }

    /// @notice Update the trusted forwarder used for ERC-2771 meta-transactions.
    function setTrustedForwarder(address newForwarder) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address prev = _trustedForwarder;
        // aderyn-ignore-next-line(state-no-address-check)
        _trustedForwarder = newForwarder;
        emit TrustedForwarderUpdated(prev, newForwarder);
    }

    /// @inheritdoc ERC2771ContextUpgradeable
    function trustedForwarder() public view override returns (address) {
        return _trustedForwarder;
    }

    function donate(uint256 amount) external {
        if (communityWallet == address(0)) revert CommunityNotSet();
        transfer(communityWallet, amount);
        emit Donated(_msgSender(), communityWallet, amount);
    }

    function rescueTokens(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(this)) revert RescueSelf();
        if (to == address(0)) revert RescueZeroRecipient();
        SafeERC20.safeTransfer(IERC20(token), to, amount);
        emit TokensRescued(token, to, amount);
    }

    // ======== Views ========

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    // ======== UUPS Auth ========

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ======== Internal Overrides ========

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20CappedUpgradeable)
    {
        super._update(from, to, value);
    }

    // ======== ERC2771 Context Overrides ========
    function _msgSender()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }

    /// @dev Reject accidental ETH transfers.
    receive() external payable { revert ETHNotAccepted(); }
    fallback() external payable { revert ETHNotAccepted(); }
}
