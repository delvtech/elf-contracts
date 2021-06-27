// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITranche.sol";

interface ICurveFi {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        returns (uint256);

    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount)
        external
        returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external returns (uint256);

    function get_dy(
        int128 from,
        int128 to,
        uint256 _from_amount
    ) external view returns (uint256);
}

contract ZapCrvERC20Generic is Authorizable {
    // Tranche factory address for Tranche contract address derivation
    address internal immutable _trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 internal immutable _trancheBytecodeHash;

    // Store the accessibility state of the contract
    bool public isFrozen = false;

    bool private _noReentry = false;

    struct ZapIn {
        // target lp token to deposit to the tranche
        IERC20 targetLp;
        // amount of input token to deposit
        uint256 amount;
        // array of pools. [target lp pool, optional 3crv]
        // a 3crv pool address can be used if the input token is part of a 3crv,
        // and the 3crv lp is the input token to the targetLp pool.
        // array should be max length 2
        ICurveFi[] pools;
        // indices of the target tokens in each pool
        // [target lp pool input token index, optional 3crv input token index]
        uint256[] indices;
        // true if the input token is part of a 3crv, and the 3crv lp is the input token
        // to the targetLp pool.
        // each pool must have a corresponding token index.
        bool in3crv;
    }

    struct ZapOut {
        // target output token to zap out to.
        IERC20 outputToken;
        // array of pools. [base lp pool, optional 3crv]
        // a 3crv pool address can be used if the output token is part of a 3crv,
        // and the 3crv lp is the input token to the base lp pool.
        // array should be max length 2
        ICurveFi[] pools;
        // indices of the target tokens in each pool
        // [target lp pool input token index, optional 3crv input token index]
        // each pool must have a corresponding token index.
        int128[] indices;
    }

    /// @dev Prevents contract reentrancy.
    /// @notice reentrancyGuarded functions should be external
    /// since they don't support calling themselves
    modifier reentrancyGuard() {
        require(!_noReentry);
        _noReentry = true;
        _;
        _noReentry = false;
    }

    /// @dev Requires that the contract is not frozen
    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    /// @dev Allows an authorized address to freeze or unfreeze this contract
    /// @param _newState True for frozen and false for unfrozen
    function setIsFrozen(bool _newState) external onlyAuthorized() {
        isFrozen = _newState;
    }

    /// @notice Constructs this contract
    /// @param __trancheFactory Address of the _trancheFactory contract
    /// @param __trancheBytecodeHash Hash of the Tranche bytecode.
    constructor(address __trancheFactory, bytes32 __trancheBytecodeHash)
        public
        Authorizable()
    {
        _trancheFactory = __trancheFactory;
        _trancheBytecodeHash = __trancheBytecodeHash;
    }

    /// @notice Approve token addresses here once so they only need to be approved once.
    /// @param _pools Curve pools to approve tokens for.
    /// @param _tokens Tokens to approve for the corresponding _pools index.
    function tokenApproval(ICurveFi[] memory _pools, IERC20[][] memory _tokens)
        external
    {
        for (uint256 i = 0; i < _pools.length; i++) {
            for (uint256 q = 0; q < _tokens[i].length; q++) {
                _tokens[i][q].approve(address(_pools[i]), type(uint256).max);
            }
        }
    }

    // Memory encoding of the permit data
    struct PermitData {
        IERC20Permit tokenContract;
        address who;
        uint256 amount;
        uint256 expiration;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /// @dev Takes the input permit calls and executes them
    /// @param data The array which encodes the set of permit calls to make
    modifier preApproval(PermitData[] memory data) {
        // If permit calls are provided we make try to make them
        if (data.length != 0) {
            // We make permit calls for each indicated call
            for (uint256 i = 0; i < data.length; i++) {
                _permitCall(data[i]);
            }
        }
        _;
    }

    /// @dev Makes permit calls indicated by a struct
    /// @param data the struct which has the permit calldata
    function _permitCall(PermitData memory data) internal {
        // Make the permit call to the token in the data field using
        // the fields provided.
        // Security note - This fairly open call is safe because it cannot
        // call 'transferFrom' or other sensitive methods despite the open
        // scope. Do not make more general without security review.
        data.tokenContract.permit(
            msg.sender,
            data.who,
            data.amount,
            data.expiration,
            data.v,
            data.r,
            data.s
        );
    }

    /// @notice This function takes an input token and converts it into yield and principal tokens
    /// of a specified tranche.
    /// @dev a tranche must exist with the output token of this function.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _ptExpected The minimum amount of principal tokens to mint.
    /// @return returns the minted amounts of principal and yield tokens minted (PT and YT)
    function zapIn(
        ZapIn memory _data,
        uint256 _expiration,
        address _position,
        uint256 _ptExpected
    ) external payable reentrancyGuard notFrozen returns (uint256, uint256) {
        require(_data.amount != 0, "0 amount");
        require(_data.pools.length == _data.indices.length, "array mismatch");
        uint256 amount = _data.amount;

        // if there are more than 1 pools, assume the second one is a 3crv
        if (_data.pools.length == 2) {
            // build the funding array
            uint256[3] memory positions;
            positions[uint256(_data.indices[1])] = _data.amount;
            // the new amount will be the 3crv lp tokens received
            amount = _data.pools[1].add_liquidity(positions, 0);
        }

        // fund the base pool to get the target LP
        uint256[2] memory positions;
        positions[_data.indices[0]] = amount;

        // amount is now the targetLp value received
        amount = _data.pools[0].add_liquidity(positions, 0);

        // transfer target lp to the tranche and call prefundedDeposit
        ITranche tranche = _deriveTranche(address(_position), _expiration);
        _data.targetLp.transfer(address(_position), amount);

        (uint256 ptMinted, uint256 ytMinted) = tranche.prefundedDeposit(
            msg.sender
        );

        require(ytMinted >= amount, "Not enough YT minted");
        require(ptMinted >= _ptExpected, "Not enough PT minted");
        return (ptMinted, ytMinted);
    }

    /// @notice This function takes principal and/or yield tokens and redeems them for an output token.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _amountPt Amount of principal tokens to redeem.
    /// @param _amountYt Amount of yield tokens to redeem.
    /// @param _outputExpected The minimum amount of principal tokens to mint.
    function zapOut(
        uint256 _expiration,
        address _position,
        uint256 _amountPt,
        uint256 _amountYt,
        uint256 _outputExpected,
        ZapOut memory _data,
        PermitData[] calldata _permitCallData
    ) external reentrancyGuard notFrozen preApproval(_permitCallData) {
        ITranche tranche = _deriveTranche(address(_position), _expiration);
        IERC20 yt;
        uint256 balance;
        // withdraw appropriate amount of lp to this contract
        if (_amountPt > 0) {
            tranche.transferFrom(msg.sender, address(this), _amountPt);
            balance += tranche.withdrawPrincipal(_amountPt, address(this));
        }
        if (_amountYt > 0) {
            yt = IERC20(tranche.interestToken());
            yt.transferFrom(msg.sender, address(this), _amountYt);
            balance += tranche.withdrawInterest(_amountYt, address(this));
        }

        require(balance > 0, "no balance");

        // balance is the output of the liquidity removal.
        balance = _data.pools[0].remove_liquidity_one_coin(
            balance,
            _data.indices[0],
            0
        );

        // if there are more than 1 pools, assume the second one is a 3crv.
        // if the output token is a 3crv lp, balance tracks the target token output amount
        if (_data.pools.length == 2) {
            balance = _data.pools[1].remove_liquidity_one_coin(
                balance,
                _data.indices[1],
                0
            );
        }

        // send the target token to the caller
        _data.outputToken.transfer(msg.sender, balance);

        require(balance >= _outputExpected, "Insufficient Output");
    }

    /// @notice There should never be any tokens in this contract.
    /// This function can rescue any possible leftovers.
    /// @param token The token to rescue.
    /// @param amount The amount to rescue.
    function rescueTokens(address token, uint256 amount)
        external
        onlyAuthorized()
    {
        IERC20 want = IERC20(token);
        want.transfer(msg.sender, want.balanceOf(address(this)));
    }

    /// @dev This internal function produces the deterministic create2
    ///      address of the Tranche contract from a wrapped position contract and expiration
    /// @param _position The wrapped position contract address
    /// @param _expiration The expiration time of the tranche
    /// @return The derived Tranche contract
    function _deriveTranche(address _position, uint256 _expiration)
        internal
        virtual
        view
        returns (ITranche)
    {
        bytes32 salt = keccak256(abi.encodePacked(_position, _expiration));
        bytes32 addressBytes = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                _trancheFactory,
                salt,
                _trancheBytecodeHash
            )
        );
        return ITranche(address(uint160(uint256(addressBytes))));
    }
}
