// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITranche.sol";

library Math {
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + (((a % 2) + (b % 2)) / 2);
    }
}

interface ISteth is IERC20 {
    function submit(address) external payable returns (uint256);
}

interface ICurveFi {
    // stETH pool
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        payable;

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external;

    function get_dy(
        int128 from,
        int128 to,
        uint256 _from_amount
    ) external view returns (uint256);
}

contract ZapSteth is Authorizable {
    // Tranche factory address for Tranche contract address derivation
    address internal immutable _trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 internal immutable _trancheBytecodeHash;
    // stETH token address
    ISteth public constant stETH = ISteth(
        address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)
    );
    // curve stable swap address
    ICurveFi public constant StableSwapSTETH = ICurveFi(
        address(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022)
    );
    // curve LP token address
    IERC20 public constant want = IERC20(
        address(0x06325440D014e39736583c165C2963BA99fAf14E)
    );
    // Store the accessibility state of the contract
    bool public isFrozen = false;

    bool private _noReentry = false;

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
    /// @param __trancheFactory Address of the TrancheFactory contract
    /// @param __trancheBytecodeHash Hash of the Tranche bytecode.
    constructor(address __trancheFactory, bytes32 __trancheBytecodeHash)
        public
        Authorizable()
    {
        _trancheFactory = __trancheFactory;
        _trancheBytecodeHash = __trancheBytecodeHash;
        want.approve(address(StableSwapSTETH), type(uint256).max);
        stETH.approve(address(StableSwapSTETH), type(uint256).max);
    }

    /// @notice Payable function so this contract can receive ETH.
    receive() external payable {}

    /// @notice This function takes ETH and converts it into yield and principal tokens
    /// of a specified tranche.
    /// @dev `_amount` must be provided as value with this function call.
    /// @param _amount Amount of ETH to convert.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _ptExpected The minimum amount of principal tokens to mint.
    /// @return returns the minted amounts of principal and yield tokens (PT and YT)
    function zapEthIn(
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _ptExpected
    ) external payable reentrancyGuard notFrozen returns (uint256, uint256) {
        require(msg.value == _amount, "Incorrect amount provided");
        ITranche tranche = _deriveTranche(address(_position), _expiration);

        uint256 balanceBegin = address(this).balance;
        if (balanceBegin < 2) return (0, 0);

        uint256 halfBal = balanceBegin / 2;
        // this is 0 if we do not buy stETH
        uint256 balance2;
        //test if we should buy instead of mint
        uint256 out = StableSwapSTETH.get_dy(0, 1, halfBal);
        if (out < halfBal) {
            balance2 = stETH.submit{ value: halfBal }(owner);
        }

        uint256 balanceMid = address(this).balance;

        //add liquidity with no minimum mint
        StableSwapSTETH.add_liquidity{ value: balanceMid }(
            [balanceMid, balance2],
            0
        );

        uint256 outAmount = want.balanceOf(address(this));

        want.transfer(address(_position), outAmount);

        (uint256 ptMinted, uint256 ytMinted) = tranche.prefundedDeposit(
            msg.sender
        );

        require(ytMinted >= outAmount, "Not enough YT minted");
        require(ptMinted >= _ptExpected, "Not enough PT minted");
        return (ptMinted, ytMinted);
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

    /// @notice This function takes stETH and converts it into yield and principal tokens
    /// of a specified tranche.
    /// @param _amount Amount of stETH to convert.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _ptExpected The minimum amount of principal tokens to mint.
    /// @return returns the minted amounts of principal and yield tokens (PT and YT)
    function zapStEthIn(
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _ptExpected
    ) external reentrancyGuard notFrozen returns (uint256, uint256) {
        require(_amount != 0, "0 stETH");
        ITranche tranche = _deriveTranche(address(_position), _expiration);
        stETH.transferFrom(msg.sender, address(this), _amount);

        uint256 balanceBegin = stETH.balanceOf(address(this));

        // add liquidity with no minimum mint
        StableSwapSTETH.add_liquidity([0, balanceBegin], 0);

        uint256 outAmount = want.balanceOf(address(this));

        want.transfer(address(_position), outAmount);

        (uint256 ptMinted, uint256 ytMinted) = tranche.prefundedDeposit(
            msg.sender
        );

        require(ytMinted >= outAmount, "Not enough YT minted");
        require(ptMinted >= _ptExpected, "Not enough PT minted");
        return (ptMinted, ytMinted);
    }

    /// @notice This function takes principal or yield tokens and redeems them for ETH.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _amountPt Amount of principal tokens to redeem.
    /// @param _amountYt Amount of yield tokens to redeem.
    /// @param _outputExpected Minimum amount of ETH or STETH to return
    function zapOutEth(
        uint256 _expiration,
        address _position,
        uint256 _amountPt,
        uint256 _amountYt,
        uint256 _outputExpected,
        PermitData[] calldata _permitCallData
    ) external reentrancyGuard notFrozen preApproval(_permitCallData) {
        _zapOut(
            _expiration,
            _position,
            _amountPt,
            _amountYt,
            _outputExpected,
            0
        );
    }

    /// @notice This function takes principal or yield tokens and redeems them for stETH.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _amountPt Amount of principal tokens to redeem.
    /// @param _amountYt Amount of yield tokens to redeem.
    /// @param _outputExpected Minimum amount of ETH or STETH to return
    function zapOutStEth(
        uint256 _expiration,
        address _position,
        uint256 _amountPt,
        uint256 _amountYt,
        uint256 _outputExpected,
        PermitData[] calldata _permitCallData
    ) external reentrancyGuard notFrozen preApproval(_permitCallData) {
        _zapOut(
            _expiration,
            _position,
            _amountPt,
            _amountYt,
            _outputExpected,
            1
        );
    }

    /// @notice There should never be any tokens in this contract.
    /// This function can rescue any possible leftovers.
    /// @param token The token to rescue.
    /// @param amount The amount to rescue.
    function rescueTokens(address token, uint256 amount)
        external
        onlyAuthorized()
    {
        if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
            amount = Math.min(address(this).balance, amount);
            payable(msg.sender).transfer(amount);
        } else {
            IERC20 want = IERC20(token);
            amount = Math.min(want.balanceOf(address(this)), amount);
            want.transfer(msg.sender, amount);
        }
    }

    /// @notice Helper function that takes principal or yield tokens and redeems them for ETH or stETH.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _amountPt Amount of principal tokens to redeem.
    /// @param _amountYt Amount of yield tokens to redeem.
    /// @param _outputExpected Minimum amount of ETH or STETH to return
    /// @param _zeroIfEth Zero if the assets to redeem for is ETH. otherwise it will be stETH.
    function _zapOut(
        uint256 _expiration,
        address _position,
        uint256 _amountPt,
        uint256 _amountYt,
        uint256 _outputExpected,
        int128 _zeroIfEth
    ) internal {
        ITranche tranche = _deriveTranche(address(_position), _expiration);
        IERC20 yt;
        uint256 balance;
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

        // balance - burn amount
        // _zeroIfEth - coin withdraw index
        // 0 - minimum amount of coin to receive
        StableSwapSTETH.remove_liquidity_one_coin(balance, _zeroIfEth, 0);

        uint256 endBalance;
        if (_zeroIfEth == 0) {
            endBalance = address(this).balance;
            payable(msg.sender).transfer(endBalance);
        } else {
            endBalance = stETH.balanceOf(address(this));
            stETH.transfer(msg.sender, endBalance);
        }
        require(endBalance >= _outputExpected, "Insufficient Output");
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
