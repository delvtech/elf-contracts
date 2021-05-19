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
    ISteth public stETH = ISteth(
        address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)
    );
    // curve stable swap address
    ICurveFi public StableSwapSTETH = ICurveFi(
        address(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022)
    );
    // curve LP token address
    IERC20 public want = IERC20(
        address(0x06325440D014e39736583c165C2963BA99fAf14E)
    );

    //slippage allowance is out of 1000. 50 is 5%
    uint256 public constant DEFAULT_SLIPPAGE = 50;
    bool private _noReentry = false;

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

    receive() external payable {}

    /// @notice This function takes ETH and converts it into yield and principal tokens
    /// of a specified tranche.
    /// @dev `_amount` must be provided as value with this function call.
    /// @param _amount Amount of ETH to convert.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _slippageAllowance The slippage allowed for the internal curve stable-swap call.
    function zapEthIn(
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _slippageAllowance
    ) external payable {
        if (_noReentry) {
            return;
        }
        require(msg.value == _amount, "Incorrect amount provided");
        ITranche tranche = _deriveTranche(address(_position), _expiration);

        uint256 balanceBegin = address(this).balance;
        if (balanceBegin < 2) return;

        uint256 halfBal = balanceBegin / 2;

        //test if we should buy instead of mint
        uint256 out = StableSwapSTETH.get_dy(0, 1, halfBal);
        if (out < halfBal) {
            stETH.submit{ value: halfBal }(owner);
        }

        uint256 balanceMid = address(this).balance;

        // this is 0 if we did not buy STETH
        uint256 balance2 = stETH.balanceOf(address(this));

        //add liquidity with no minimum mint
        StableSwapSTETH.add_liquidity{ value: balanceMid }(
            [balanceMid, balance2],
            0
        );

        uint256 outAmount = want.balanceOf(address(this));

        require(
            (outAmount * (_slippageAllowance + 10000)) / 10000 >= balanceBegin,
            "TOO MUCH SLIPPAGE"
        );
        want.transfer(address(_position), outAmount);
        tranche.prefundedDeposit(msg.sender);
    }

    /// @notice This function takes stETH and converts it into yield and principal tokens
    /// of a specified tranche.
    /// @param _amount Amount of stETH to convert.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _slippageAllowance The slippage allowed for the internal curve stable-swap call.
    function zapStEthIn(
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _slippageAllowance
    ) external {
        require(_amount != 0, "0 stETH");
        ITranche tranche = _deriveTranche(address(_position), _expiration);
        stETH.transferFrom(msg.sender, address(this), _amount);

        uint256 balanceBegin = stETH.balanceOf(address(this));
        require(balanceBegin + 1 >= _amount, "NOT ALL stETH RECEIVED");

        // add liquidity with no minimum mint
        StableSwapSTETH.add_liquidity([0, balanceBegin], 0);

        uint256 outAmount = want.balanceOf(address(this));

        require(
            (outAmount * (_slippageAllowance + 10000)) / 10000 >= balanceBegin,
            "TOO MUCH SLIPPAGE"
        );

        want.transfer(address(_position), outAmount);

        tranche.prefundedDeposit(msg.sender);
    }

    /// @notice This function takes principal or yield tokens and redeems them for ETH.
    /// @param _amount Amount of PT or YT to withdraw.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _slippageAllowance The slippage allowed for the internal curve stable-swap call.
    /// @param _zeroIfPrincipal Zero if the assets to redeem are principal tokens.
    function zapOutEth(
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _slippageAllowance,
        int128 _zeroIfPrincipal
    ) external {
        _zapOut(
            _amount,
            _expiration,
            _position,
            _slippageAllowance,
            _zeroIfPrincipal,
            0
        );
    }

    /// @notice This function takes principal or yield tokens and redeems them for stETH.
    /// @param _amount Amount of PT or YT to withdraw.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _slippageAllowance The slippage allowed for the internal curve stable-swap call.
    /// @param _zeroIfPrincipal Zero if the assets to redeem are principal tokens.
    function zapOutStEth(
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _slippageAllowance,
        int128 _zeroIfPrincipal
    ) external {
        _zapOut(
            _amount,
            _expiration,
            _position,
            _slippageAllowance,
            _zeroIfPrincipal,
            1
        );
    }

    /// @notice There should never be any tokens in this contract.
    /// This function can rescue any possible leftovers.
    /// @param token The token to rescue.
    /// @param amount The amount to rescue.
    function rescueTokens(address token, uint256 amount) external onlyOwner {
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
    /// @param _amount Amount of PT or YT to withdraw.
    /// @param _expiration Expiration of the target tranche.
    /// @param _position The wrapped position contract address.
    /// @param _slippageAllowance The slippage allowed for the internal curve stable-swap call.
    /// @param _zeroIfPrincipal Zero if the assets to redeem are principal tokens.
    /// @param _zeroIfEth Zero if the assets to redeem for is ETH. otherwise it will be stETH.
    function _zapOut(
        uint256 _amount,
        uint256 _expiration,
        address _position,
        uint256 _slippageAllowance,
        int128 _zeroIfPrincipal,
        int128 _zeroIfEth
    ) internal {
        ITranche tranche = _deriveTranche(address(_position), _expiration);

        if (_zeroIfPrincipal == 0) {
            tranche.transferFrom(msg.sender, address(this), _amount);
            tranche.approve(address(tranche), _amount);
            tranche.withdrawPrincipal(_amount, address(this));
        } else {
            IERC20 yt = IERC20(tranche.interestToken());
            yt.transferFrom(msg.sender, address(this), _amount);
            yt.approve(address(tranche), _amount);
            tranche.withdrawInterest(_amount, address(this));
        }

        uint256 balance = want.balanceOf(address(this));
        require(balance > 0, "no balance");

        _noReentry = true;
        // balance - burn amount
        // _zeroIfEth - coin withdraw index
        // 0 - minimum amount of coin to receive
        StableSwapSTETH.remove_liquidity_one_coin(balance, _zeroIfEth, 0);
        _noReentry = false;

        uint256 endBalance;
        if (_zeroIfEth == 0) {
            endBalance = address(this).balance;
            payable(msg.sender).transfer(endBalance);
        } else {
            endBalance = stETH.balanceOf(address(this));
            stETH.transfer(msg.sender, endBalance);
        }
        require(
            (endBalance * (_slippageAllowance + 10000)) / 10000 >= balance,
            "TOO MUCH SLIPPAGE"
        );

        uint256 leftover = tranche.balanceOf(address(this));
        if (leftover > 0) {
            tranche.transfer(msg.sender, endBalance);
        }
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
