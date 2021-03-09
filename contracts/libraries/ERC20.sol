// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IERC20Permit.sol";

abstract contract ERC20 is IERC20Permit {
    // --- ERC20 Data ---
    string public name;
    string public override symbol;
    uint8 public override decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    mapping(address => uint256) public override nonces;

    // --- EIP712 niceties ---
    bytes32 public override DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
    bytes32
        public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        decimals = 18;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                _getChainId(),
                address(this)
            )
        );
    }

    // --- Token ---
    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        return transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address spender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(balanceOf[spender] >= amount, "ERC20: insufficient-balance");
        if (
            spender != msg.sender &&
            allowance[spender][msg.sender] != type(uint256).max
        ) {
            require(
                allowance[spender][msg.sender] >= amount,
                "ERC20: insufficient-allowance"
            );
            allowance[spender][msg.sender] =
                allowance[spender][msg.sender] -
                amount;
        }
        balanceOf[spender] = balanceOf[spender] - amount;
        balanceOf[recipient] = balanceOf[recipient] + amount;
        emit Transfer(spender, recipient, amount);
        return true;
    }

    function _mint(address account, uint256 amount) internal virtual {
        balanceOf[account] = balanceOf[account] + amount;
        totalSupply = totalSupply + amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        balanceOf[account] = balanceOf[account] - amount;
        totalSupply = totalSupply - amount;
        emit Transfer(account, address(0), amount);
    }

    function approve(address account, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        allowance[msg.sender][account] = amount;
        emit Approval(msg.sender, account, amount);
        return true;
    }

    // --- Approve by signature ---
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
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

        require(owner != address(0), "ERC20: invalid-address-0");
        require(owner == ecrecover(digest, v, r, s), "ERC20: invalid-permit");
        require(deadline == 0 || block.timestamp <= deadline, "ERC20: permit-expired");
        nonces[owner]++;
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _setupDecimals(uint8 decimals_) internal {
        decimals = decimals_;
    }

    function _getChainId() private view returns (uint256 chainId) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
    }
}
