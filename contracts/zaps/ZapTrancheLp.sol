// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../libraries/Authorizable.sol";
import "../interfaces/IERC20Permit.sol";
import "../interfaces/ITranche.sol";
import "../interfaces/IWrappedPosition.sol";
import "../interfaces/IInterestToken.sol";

interface IPool {
    function bond() external view returns (address);
}

interface IAsset {}

interface IVault {
    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;

    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }
}

interface ITrancheExt is ITranche {
    function position() external view returns (IWrappedPosition);

    function underlying() external view returns (IERC20);
}

contract ZapTrancheLp is Authorizable {
    // Store the accessibility state of the contract
    bool public isFrozen = false;

    // The balancer Vault contract
    IVault internal _vault;

    constructor(address __vault) Authorizable() {
        _authorize(msg.sender);
        _vault = IVault(__vault);
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

    struct Out {
        bytes32 poolId;
        IVault.ExitPoolRequest request;
    }

    struct In {
        uint256 lpCheck;
        bytes32 poolId;
        IVault.JoinPoolRequest request;
    }

    /// @notice Removes PT + YT liquidity from balancer pools, withdraws the PT + YT,
    /// deposits into a new Tranche, and joins new PT and YT liquidity pools.
    /// @dev The
    /// @param _toMint The amount of underlying to mint with in the new tranche.
    /// @param _ptOutInfo Out struct with info to exit the lp position for the pt.
    /// @param _ytOutInfo Out struct with info to exit the lp position for the yt.
    /// @param _ptInInfo In struct with info to enter the new lp position for the pt.
    /// @param _ytInInfo In struct with info to enter the new lp position for the yt.
    /// @param _onlyPrincipal This can be set to true to avoid any yt actions.
    /// @param _permitCallData Encoded array of permit calls to make prior to minting
    ///                        the data should be encoded with abi.encode(data, "PermitData[]")
    ///                        each PermitData struct provided will be executed as a call.
    ///                        An example use of this is if using a token with permit like USDC
    ///                        to encode a permit which gives this contract allowance before minting.
    function hopToTranche(
        uint256 _toMint,
        Out memory _ptOutInfo,
        Out memory _ytOutInfo,
        In memory _ptInInfo,
        In memory _ytInInfo,
        bool _onlyPrincipal,
        PermitData[] calldata _permitCallData
    ) public notFrozen {
        IERC20 ytPool;
        // get tranches
        ITrancheExt trancheFrom = ITrancheExt(
            IPool(address(uint160(uint256(_ptOutInfo.poolId)) >> (12 * 8)))
                .bond()
        );

        ITrancheExt trancheTo = ITrancheExt(
            IPool(address(uint160(uint256(_ptInInfo.poolId)) >> (12 * 8)))
                .bond()
        );

        // transfer pt lp tokens
        IERC20 ptPool = IERC20(
            address(uint160(uint256(_ptOutInfo.poolId)) >> (12 * 8))
        );
        ptPool.transferFrom(
            msg.sender,
            address(this),
            ptPool.balanceOf(msg.sender)
        );

        // exit PT position
        _vault.exitPool(
            _ptOutInfo.poolId,
            address(this),
            payable(address(this)),
            _ptOutInfo.request
        );

        // withdraw principal here. This should accumulate underlying.
        trancheFrom.withdrawPrincipal(
            trancheFrom.balanceOf(address(this)),
            address(this)
        );

        if (!_onlyPrincipal) {
            // transfer yt lp tokens
            ytPool = IERC20(
                address(uint160(uint256(_ytOutInfo.poolId)) >> (12 * 8))
            );
            ytPool.transferFrom(
                msg.sender,
                address(this),
                ytPool.balanceOf(msg.sender)
            );

            // exit YT position
            _vault.exitPool(
                _ytOutInfo.poolId,
                address(this),
                payable(address(this)),
                _ytOutInfo.request
            );

            // withdraw interest to the new tranche to prep a pre-funded deposit
            trancheFrom.withdrawInterest(
                IERC20(address(trancheFrom.interestToken())).balanceOf(
                    address(this)
                ),
                address(this)
            );
        }

        // transfer required amount and run prefunded deposit
        trancheFrom.underlying().transfer(
            address(trancheTo.position()),
            _toMint
        );
        trancheTo.prefundedDeposit(address(this));

        uint256 ptLpBalanceBefore = ptPool.balanceOf(msg.sender);
        // enter new PT position
        _vault.joinPool(
            _ptInInfo.poolId,
            address(this),
            payable(msg.sender), // hardcode for security
            _ptInInfo.request
        );
        uint256 ptLpBalanceAfter = ptPool.balanceOf(msg.sender);

        require(
            ptLpBalanceAfter - ptLpBalanceBefore >= _ptInInfo.lpCheck,
            "not enough PT LP minted"
        );

        if (!_onlyPrincipal) {
            uint256 ytLpBalanceBefore = ytPool.balanceOf(msg.sender);
            // enter new YT position
            _vault.joinPool(
                _ytInInfo.poolId,
                address(this),
                payable(msg.sender),
                _ytInInfo.request
            );
            uint256 ytLpBalanceAfter = ptPool.balanceOf(msg.sender);
            require(
                ytLpBalanceAfter - ytLpBalanceBefore >= _ytInInfo.lpCheck,
                "not enough PT LP minted"
            );
        }

        // recover any dust
        IERC20 yt = IERC20(address(trancheFrom.interestToken()));
        IERC20 t1 = IERC20(address(_ptOutInfo.request.assets[0]));
        IERC20 t2 = IERC20(address(_ptOutInfo.request.assets[1]));

        yt.transfer(msg.sender, yt.balanceOf(address(this)));
        t1.transfer(msg.sender, t1.balanceOf(address(this)));
        t2.transfer(msg.sender, t2.balanceOf(address(this)));
    }

    /// @notice Approve token addresses here once so they only need to be approved once.
    /// @param _tokens Tokens to approve.
    /// @param _tokens Targets for each token approval.
    function tokenApproval(IERC20[] memory _tokens, address[] memory _targets)
        external
        onlyAuthorized
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _tokens[i].approve(_targets[i], type(uint256).max);
        }
    }
}
