// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../interfaces/IERC20Permit.sol";

// This default erc20 library is designed for max efficiency and security.
// WARNING: By default it does not include totalSupply which breaks the ERC20 standard
//          to use a fully standard compliant ERC20 use 'ERC20PermitWithSupply"
abstract contract ERC20Permit is IERC20Permit {
    // --- ERC20 Data ---
    // The name of the erc20 token
    string public name;
    // The symbol of the erc20 token
    string public override symbol;
    // The decimals of the erc20 token, should default to 18 for new tokens
    uint8 public override decimals;

    // A mapping which tracks user token balances
    mapping(address => uint256) public override balanceOf;
    // A mapping which tracks which addresses a user allows to move their tokens
    mapping(address => mapping(address => uint256)) public override allowance;
    // A mapping which tracks the permit signature nonces for users
    mapping(address => uint256) public override nonces;

    // --- EIP712 niceties ---
    // solhint-disable-next-line var-name-mixedcase
    bytes32 public override DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice Initializes the erc20 contract
    /// @param name_ the value 'name' will be set to
    /// @param symbol_ the value 'symbol' will be set to
    /// @dev decimals default to 18 and must be reset by an inheriting contract for
    ///      non standard decimal values
    constructor(string memory name_, string memory symbol_) {
        // Set the state variables
        name = name_;
        symbol = symbol_;
        decimals = 18;

        // By setting these addresses to 0 attempting to execute a transfer to
        // either of them will revert. This is a gas efficient way to prevent
        // a common user mistake where they transfer to the token address.
        // These values are not considered 'real' tokens and so are not included
        // in 'total supply' which only contains minted tokens.
        balanceOf[address(0)] = type(uint256).max;
        balanceOf[address(this)] = type(uint256).max;

        // Optional extra state manipulation
        _extraConstruction();

        // Computes the EIP 712 domain separator which prevents user signed messages for
        // this contract to be replayed in other contracts.
        // https://eips.ethereum.org/EIPS/eip-712
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice An optional override function to execute and change state before immutable assignment
    function _extraConstruction() internal virtual {}

    // --- Token ---
    /// @notice Allows a token owner to send tokens to another address
    /// @param recipient The address which will be credited with the tokens
    /// @param amount The amount user token to send
    /// @return returns true on success, reverts on failure so cannot return false.
    /// @dev transfers to this contract address or 0 will fail
    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        // We forward this call to 'transferFrom'
        return transferFrom(msg.sender, recipient, amount);
    }

    /// @notice Transfers an amount of erc20 from a spender to a receipt
    /// @param spender The source of the ERC20 tokens
    /// @param recipient The destination of the ERC20 tokens
    /// @param amount the number of tokens to send
    /// @return returns true on success and reverts on failure
    /// @dev will fail transfers which send funds to this contract or 0
    function transferFrom(
        address spender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        // Load balance and allowance
        uint256 balance = balanceOf[spender];
        require(balance >= amount, "ERC20: insufficient-balance");
        // We potentially have to change allowances
        if (spender != msg.sender) {
            // Loading the allowance in the if block prevents vanilla transfers
            // from paying for the sload.
            uint256 allowed = allowance[spender][msg.sender];
            // If the allowance is max we do not reduce it
            // Note - This means that max allowances will be more gas efficient
            // by not requiring a sstore on 'transferFrom'
            if (allowed != type(uint256).max) {
                require(allowed >= amount, "ERC20: insufficient-allowance");
                allowance[spender][msg.sender] = allowed - amount;
            }
        }
        // Update the balances
        balanceOf[spender] = balance - amount;
        // Note - In the constructor we initialize the 'balanceOf' of address 0 and
        //        the token address to uint256.max and so in 8.0 transfers to those
        //        addresses revert on this step.
        balanceOf[recipient] = balanceOf[recipient] + amount;
        // Emit the needed event
        emit Transfer(spender, recipient, amount);
        // Return that this call succeeded
        return true;
    }

    /// @notice This internal minting function allows inheriting contracts
    ///         to mint tokens in the way they wish.
    /// @param account the address which will receive the token.
    /// @param amount the amount of token which they will receive
    /// @dev This function is virtual so that it can be overridden, if you
    ///      are reviewing this contract for security you should ensure to
    ///      check for overrides
    function _mint(address account, uint256 amount) internal virtual {
        // Add tokens to the account
        balanceOf[account] = balanceOf[account] + amount;
        // Emit an event to track the minting
        emit Transfer(address(0), account, amount);
    }

    /// @notice This internal burning function allows inheriting contracts to
    ///         burn tokens in the way they see fit.
    /// @param account the account to remove tokens from
    /// @param amount  the amount of tokens to remove
    /// @dev This function is virtual so that it can be overridden, if you
    ///      are reviewing this contract for security you should ensure to
    ///      check for overrides
    function _burn(address account, uint256 amount) internal virtual {
        // Reduce the balance of the account
        balanceOf[account] = balanceOf[account] - amount;
        // Emit an event tracking transfers
        emit Transfer(account, address(0), amount);
    }

    /// @notice This function allows a user to approve an account which can transfer
    ///         tokens on their behalf.
    /// @param account The account which will be approve to transfer tokens
    /// @param amount The approval amount, if set to uint256.max the allowance does not go down on transfers.
    /// @return returns true for compatibility with the ERC20 standard
    function approve(address account, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        // Set the senders allowance for account to amount
        allowance[msg.sender][account] = amount;
        // Emit an event to track approvals
        emit Approval(msg.sender, account, amount);
        return true;
    }

    /// @notice This function allows a caller who is not the owner of an account to execute the functionality of 'approve' with the owners signature.
    /// @param owner the owner of the account which is having the new approval set
    /// @param spender the address which will be allowed to spend owner's tokens
    /// @param value the new allowance value
    /// @param deadline the timestamp which the signature must be submitted by to be valid
    /// @param v Extra ECDSA data which allows public key recovery from signature assumed to be 27 or 28
    /// @param r The r component of the ECDSA signature
    /// @param s The s component of the ECDSA signature
    /// @dev The signature for this function follows EIP 712 standard and should be generated with the
    ///      eth_signTypedData JSON RPC call instead of the eth_sign JSON RPC call. If using out of date
    ///      parity signing libraries the v component may need to be adjusted. Also it is very rare but possible
    ///      for v to be other values, those values are not supported.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        // The EIP 712 digest for this function
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner],
                        deadline
                    )
                )
            )
        );
        // Require that the owner is not zero
        require(owner != address(0), "ERC20: invalid-address-0");
        // Require that we have a valid signature from the owner
        require(owner == ecrecover(digest, v, r, s), "ERC20: invalid-permit");
        // Require that the signature is not expired
        require(
            deadline == 0 || block.timestamp <= deadline,
            "ERC20: permit-expired"
        );
        // Format the signature to the default format
        require(
            uint256(s) <=
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "ERC20: invalid signature 's' value"
        );
        // Increment the signature nonce to prevent replay
        nonces[owner]++;
        // Set the allowance to the new value
        allowance[owner][spender] = value;
        // Emit an approval event to be able to track this happening
        emit Approval(owner, spender, value);
    }

    /// @notice Internal function which allows inheriting contract to set custom decimals
    /// @param decimals_ the new decimal value
    function _setupDecimals(uint8 decimals_) internal {
        // Set the decimals
        decimals = decimals_;
    }
}
