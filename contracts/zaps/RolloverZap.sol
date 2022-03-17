// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "../RolloverAssetProxy.sol";
import "../interfaces/ITranche.sol";
import "../interfaces/IVault.sol";
import "../libraries/Authorizable.sol";
import "../interfaces/IERC20.sol";

interface ITrancheExt is ITranche {
    function position() external view returns (IWrappedPosition);

    function underlying() external view returns (IERC20);
}

contract RolloverZap is Authorizable {
    IVault public balancer;
    uint256 public immutable dustReturnThresholdLp;
    uint256 public immutable dustReturnThresholdUnderlying;
    // Store the accessibility state of the contract
    bool public isFrozen = false;

    /// @notice - Constructs the contract and sets state variables
    /// @param _governance The address which can add or remove an approved upgrador
    /// @param _balancer The address of the balancer vault
    constructor(
        IVault _balancer,
        address _governance,
        uint256 _dustReturnThresholdLp,
        uint256 _dustReturnThresholdUnderlying
    ) Authorizable() {
        setOwner(_governance);
        _authorize(msg.sender);
        balancer = _balancer;
        dustReturnThresholdLp = _dustReturnThresholdLp;
        dustReturnThresholdUnderlying = _dustReturnThresholdUnderlying;
    }

    /// @dev Requires that the contract is not frozen
    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    /// @dev Allows an authorized address to freeze or unfreeze this contract
    /// @param _newState True for frozen and false for unfrozen
    function setIsFrozen(bool _newState) external onlyAuthorized {
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

    struct ZapData {
        // ID of balancer pool trading rollover internal tranche principal token.
        bytes32 balancerPoolID;
        // balancer pool join request struct.
        IVault.JoinPoolRequest request;
        // rollover tranche address. The tranche that uses the Rollover Asset Proxy.
        ITrancheExt rolloverTranche;
        // Underlying token of the Rollover underlying tranche.
        IERC20 token;
        // total amount of underlying to deposit.
        uint256 totalAmount;
        // total amount of underlying to deposit into rollover internal tranche.
        uint256 depositAmount;
        // beneficiary of any actions taken by the zap.
        address receiver;
        // optional permit data.
        PermitData[] permitCallData;
    }

    /// @dev Takes the input permit calls and executes them
    /// @param data The array which encodes the set of permit calls to make
    modifier preApproval(PermitData[] memory data) {
        // If permit calls are provided we try to make them
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

    /// @notice Zaps into the auto rollover tranche regardless of settlement period status.
    /// @param _data Data required for the zap.
    function deposit(ZapData calldata _data)
        public
        notFrozen
        preApproval(_data.permitCallData)
    {
        // get the rollover proxy by querying the position of the rollover tranche
        RolloverAssetProxy proxy = RolloverAssetProxy(
            address(_data.rolloverTranche.position())
        );
        // the target tranche is the underlying tranche of the rollover proxy
        ITranche targetTranche = proxy.tranche();
        // get yield token same way
        IERC20 yieldToken = proxy.yieldToken();

        // Transfer the entire underlying balance to the contract
        _data.token.transferFrom(msg.sender, address(this), _data.totalAmount);

        // if the rollover proxy is in settlement we deposit directly and end the zap
        if (proxy.baseSupply() != 0 || proxy.totalSupply() == 0) {
            _data.token.transfer(address(proxy), _data.totalAmount);
            _data.rolloverTranche.prefundedDeposit(_data.receiver);
            return;
        }

        // if we are not in settlement join the tranche to get PT and YT.
        // The amount to deposit here is calculated off-chain.
        (uint256 ptMinted, uint256 ytMinted) = targetTranche.deposit(
            _data.depositAmount,
            address(this)
        );

        // join the balance pool to get LP. The join parameters are calculated off-chain
        balancer.joinPool(
            _data.balancerPoolID,
            address(this),
            address(this),
            _data.request
        );

        // derive the address of the LP token the same way balancer internally.
        IERC20 lp = IERC20(
            address(uint160(uint256(_data.balancerPoolID) >> (12 * 8)))
        );

        // balance variable to be reused for various balances. Single variable to cut on stack.
        // first tracks balancer LP balance.
        uint256 balance = lp.balanceOf(address(this));

        // calculate correct ratio and send, maximum funds using correct ratio.
        uint256 proxyLpBalance = uint256(proxy.lpSupply());
        uint256 proxyYtBalance = uint256(proxy.ytSupply());
        // check if we have enough yield tokens to satisfy the ratio with the current LP balance
        uint256 yieldIn = (balance * proxyYtBalance) / proxyLpBalance;

        // use correct amount of tokens to match ratio
        if (yieldIn < ytMinted) {
            // send back remaining yield token balance if over threshold
            if (ytMinted - yieldIn >= dustReturnThresholdUnderlying) {
                yieldToken.transfer(_data.receiver, ytMinted - yieldIn);
            }
            ytMinted = yieldIn;
        }
        // calculate the correct amount of LP tokens to send given the amount of YTs available
        uint256 lpIn = (proxyLpBalance * ytMinted) / proxyYtBalance;
        // transfer yt and lp in order to run prefundedDeposit
        yieldToken.transfer(address(proxy), ytMinted);
        lp.transfer(address(proxy), lpIn);
        _data.rolloverTranche.prefundedDeposit(_data.receiver);

        // send back remaining tokens
        balance = lp.balanceOf(address(this));
        if (balance >= dustReturnThresholdLp) {
            lp.transfer(_data.receiver, balance);
        }
        balance = _data.token.balanceOf(address(this));
        if (balance >= dustReturnThresholdUnderlying) {
            _data.token.transfer(_data.receiver, balance);
        }
        balance = targetTranche.balanceOf(address(this));
        if (balance >= dustReturnThresholdUnderlying) {
            targetTranche.transfer(_data.receiver, balance);
        }
    }

    /// @notice Approve token addresses here once so they only need to be approved once.
    /// @param _tokens Tokens to approve.
    /// @param _targets Targets for each token approval.
    function tokenApproval(IERC20[] memory _tokens, address[] memory _targets)
        external
        onlyAuthorized
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _tokens[i].approve(_targets[i], type(uint256).max);
        }
    }
}
