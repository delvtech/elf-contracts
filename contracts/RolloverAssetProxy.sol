// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./WrappedPosition.sol";
import "./libraries/Authorizable.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IVault.sol";

import "hardhat/console.sol";

/// @author Element Finance
/// @title Rollover Asset Proxy
contract RolloverAssetProxy is WrappedPosition, Authorizable {
    // The Rollover asset proxy allows users to enter and have their funds rollover
    // to a LP in a new term each time an old term expires.
    // The mechanics of rollover are slightly more complex than other wrapped positions
    // this is because it employs a scheduling mechanic with two types of periods: a
    // settlement period and a committed period. During the settlement period the wrapped
    // position holds funds entirely in the underlying asset [eg WETH, USDC, DAI], and during
    // the committed period it holds PT-LP tokens and YT tokens in a term.
    // WARNING - Tranches based on this asset proxy must expire and redeem in settlement period.
    // WARNING - Committed period break the deposit method

    // Governance chooses which terms to upgrade to and coordinates settlement periods so using
    // this tranche includes some exposure to governance risk.

    // The total supply of the wrapped position tokens
    uint128 public totalSupply;
    // The amount of underlying this contract holds
    uint128 public baseSupply;
    // The amount of LP token this contract holds
    uint128 public lpSupply;
    // The amount of yield token this contract holds
    uint128 public ytSupply;

    // We track the underlying invested at the beginning of the term
    uint256 public impliedBaseSupply;

    // We store the info on the current tranche this system is LP-ing for
    ITranche public tranche;
    // We also store the balancer pool id of the current LP token
    bytes32 public balancerPoolID;
    // We cache this data even though it is loadable to save gas
    IERC20 public balancerPoolAddress;
    IERC20 public yieldToken;

    // When governance attempts a rollover they must wait a predefined time set on construction
    uint128 public newTermRegistered;
    // The min wait time is to be set by a full protocol vote, instead of managed by an authorized
    // rollover handler address.
    uint128 public minWaitTime;
    // A storage variable containing the balancer vault address
    IVault public balancer;

    // Constants which represent an acceptable loss of funds in dust.
    uint256 public immutable baseDustThreshold;
    uint256 public immutable lpDustThreshold;

    /// @notice - Constructs the contract and sets stat variables
    /// @param _governance The address which can add or remove an approved upgrador
    /// @param _upgrador The first address which can cycle terms
    /// @param _balancer The address of the balancer vault
    /// @param _baseDustThreshold The amount of underlying token which is considered dust
    /// @param _lpDustThreshold The amount of LP which is considered dust
    /// @param _minWaitTime The minium wait period between a new term proposal and a rollover
    /// @param _token The address of the underlying token
    /// @param _name The name of the wrapped position token
    /// @param _symbol The symbol of the wrapped position token
    /// @dev Dust thresholds are expected to be calculated so that for the decimals of each asset type and
    ///      value that they are above rounding error thresholds and of minimal economic value.
    constructor(
        address _governance,
        address _upgrador,
        IVault _balancer,
        uint256 _baseDustThreshold,
        uint256 _lpDustThreshold,
        uint256 _minWaitTime,
        IERC20 _token,
        string memory _name,
        string memory _symbol
    ) Authorizable() WrappedPosition(_token, _name, _symbol) {
        // Authorize the upgrador and set the owner
        _authorize(_upgrador);
        setOwner(_governance);
        // Set state and immutables
        minWaitTime = uint128(_minWaitTime);
        balancer = _balancer;
        _token.approve(address(_balancer), type(uint256).max);
        baseDustThreshold = _baseDustThreshold;
        lpDustThreshold = _lpDustThreshold;
    }

    /// @notice This override function defines how deposits are handled into the wrapped position.
    ///         It has two periods, one where it only holds underlying [called settlement] and one
    ///         where it holds both principal token LP and yield tokens [called committed]. Deposits
    ///         during both periods receive shares equal to the value increase of the contract. In
    ///         settlement the value increase must be in underlying, and in commitment it must be in
    ///         yt and principal token LP shares.
    /// @dev    The commit period requiring a two token deposit breaks the normal deposit method in the
    ///         wrapped position, the contract must be used with prefunded deposit. For security reasons
    ///         the prefunded deposit MUST come from a smart contract which does atomic transactions to fund
    ///         this contract.
    /// @return Returns shares created and an underestimate of the amount they are worth.
    function _deposit() internal override returns (uint256, uint256) {
        // First we check on if we are in a settlement or commitment period by checking
        // the reserve of the underlying
        uint256 localTotalSupply = uint256(totalSupply);
        uint256 localBaseSupply = uint256(baseSupply);

        if (localBaseSupply != 0 || localTotalSupply == 0) {
            // If the underlying token supplied are not zero we are in a settlement period
            // so deposits are simply an increase in underlying and the share percent it represents.
            uint256 actualTokenBalance = token.balanceOf(address(this));
            uint256 amountDeposited = actualTokenBalance - localBaseSupply;
            // Calculate how many shares this is worth
            uint256 shares = localTotalSupply == 0
                ? amountDeposited
                : (localTotalSupply * amountDeposited) / localBaseSupply;
            // Update the base reserves and total supply
            baseSupply = uint128(actualTokenBalance);
            totalSupply += uint128(shares);
            // Return the shares minted and amount
            return (shares, amountDeposited);
        } else {
            // We require that if you join outside a settlement period you must provide the same
            // proportion of lp and yield token into the reserves
            uint256 actualYTBalance = uint256(
                yieldToken.balanceOf(address(this))
            );
            uint256 actualLPBalance = uint256(
                balancerPoolAddress.balanceOf(address(this))
            );
            uint256 depositedYT = actualYTBalance - ytSupply;
            uint256 depositedLP = actualLPBalance - lpSupply;
            // Calculate the shares implied by the ratio
            uint256 shares = (depositedYT * localTotalSupply) / ytSupply;
            // Now require that the deposited amounts correctly ratio match
            // We add a factor to preserve decimals
            // TODO - Do some real analysis on this
            require(
                shares == (depositedLP * localTotalSupply) / lpSupply,
                "Incorrect Ratio"
            );
            // Note - Without this check if someone calls deposit and transfers underlying
            //        to this contract it will not revert but they will get zero shares
            require(shares != 0, "No deposit");
            // Now we calculate the implied amount this increases the value in the term
            // WARNING - This number is wrong and does not include interest.
            uint256 impliedUnderlying = (impliedBaseSupply * depositedYT) /
                ytSupply;
            // State updates
            ytSupply = uint128(actualLPBalance);
            lpSupply = uint128(actualYTBalance);
            totalSupply += uint128(shares);
            impliedBaseSupply += impliedUnderlying;
            // Return the shares to be minted and the implied underlying this is worth
            return (shares, impliedUnderlying);
        }
    }

    /// @notice The implementation of the withdraw function inherited from wrapped position
    ///         this function either gives out a proportion of the underlying or the LP/YT
    ///         held by this depending on if it is in a settlement or commitment period
    ///         respectively. Warning - In a commitment period it only estimates the value
    ///         of the unlocked tokens and that estimate is a strict under estimate.
    /// @param shares The number of wrapped position shares to remove
    /// @param destination The address to which the shares will be sent
    // @param underlyingPerShare unused in this implementation
    /// @return In settlement period returns the amount of underlying released or in
    ///         a committed period returns an underestimate of the value of the LP+YT released.
    function _withdraw(
        uint256 shares,
        address destination,
        uint256
    ) internal override returns (uint256) {
        // First we check on if we are in a settlement or commitment period by checking
        // the reserve of the underlying
        uint256 localTotalSupply = uint256(totalSupply);
        uint256 localBaseSupply = uint256(baseSupply);

        if (localBaseSupply != 0) {
            // In settlement periods we pay out purely proportionally
            uint256 amount = (shares * localBaseSupply) / localTotalSupply;
            // We then adjust state
            totalSupply -= uint128(shares);
            baseSupply -= uint128(amount);
            // Send the user the withdrawn funds
            token.transfer(destination, amount);
            // return the amount sent
            return (amount);
        } else {
            // First load the reserves
            uint256 localLPSupply = uint256(lpSupply);
            uint256 localYTSupply = uint256(ytSupply);
            // In the non settlement period we set an LP token and YT token according to proportion
            uint256 amountLP = (shares * localLPSupply) / localTotalSupply;
            uint256 amountYT = (shares * localYTSupply) / localTotalSupply;
            // Estimate the amount of underlying this worth
            // NOTE - This is a strict under estimate.
            uint256 underlyingEstimate = (shares * uint256(impliedBaseSupply)) /
                localTotalSupply;
            // Transfer the respective tokens
            balancerPoolAddress.transfer(destination, amountLP);
            yieldToken.transfer(destination, amountYT);
            // Adjust the state
            lpSupply -= uint128(amountLP);
            ytSupply -= uint128(amountYT);
            totalSupply -= uint128(shares);
            impliedBaseSupply -= uint128(underlyingEstimate);
            // Return the underestimate of how much this is worth.
            return (underlyingEstimate);
        }
    }

    /// @notice Implements a method in wrapped position and returns an estimate of share
    ///         value. Warning - During commitment periods this is a strict under estimate
    /// @param shares The number of shares to get the value of
    /// @return The estimated value
    function _underlying(uint256 shares)
        internal
        view
        override
        returns (uint256)
    {
        // Check if we are in a settlement period
        if (baseSupply != 0) {
            // Give a strict proportion of the base supply
            return ((uint256(baseSupply) * shares) / uint256(totalSupply));
        } else {
            // Warning - this underestimates the share value.
            return ((impliedBaseSupply * shares) / uint256(totalSupply));
        }
    }

    // Note - The following functions are used by governance to rollover the tranche which holds the user funds
    //        When a term expires the governance removes funds and enters an adjustable length implicit easy withdraw
    //        or deposit period by holding only the underlying. This is implicitly checked by checking the local
    //        supply of LP tokens. When a new term is added the held underlying are placed into a new term.

    /// @notice Allows an authorized user to register which term will be entered into in the future. This has
    ///         two purposes (1) to guarantee some settlement time for easy withdraw (2) add resilience to attacks
    ///         where an authorized user attempts to steal funds, since in the transition time allows users to exit
    ///         and governance to remove the bad authorized rollover-er.
    /// @param _tranche The address of the new PT/YT terms to use
    /// @param _balancerPoolID The pool ID of the Balancer pool this rollover uses
    function registerNewTerm(ITranche _tranche, bytes32 _balancerPoolID)
        external
        onlyAuthorized
    {
        // First we do a check that we are not in a term
        require(
            lpSupply == 0 && ytSupply == 0,
            "Rollover attempted at wrong time"
        );
        // Note - We do not check however for zero-ness of the tranche address because it is
        // allowed to change which term will be upgraded too
        // Next we set all state variables.
        tranche = _tranche;
        balancerPoolID = _balancerPoolID;
        newTermRegistered = uint128(block.timestamp);
        // Load the yield token and store it
        yieldToken = _tranche.interestToken();
        // Load the balancer pool address and store it
        (address poolAddress, ) = balancer.getPool(_balancerPoolID);
        balancerPoolAddress = IERC20(poolAddress);
    }

    /// @notice Moves the assets held by the contract into the new term by creating PT/YT
    ///         and then adding it as LP in the the new Balancer Pool.
    /// @param _mintAmount The amount of underlying to add to the new tranche
    /// @param request A balancer v2 compatible request struct with the information on how
    ///                the AMM turns the underlying into LP shares.
    /// @dev The authorized address should do the work of calculating the how much to mint
    ///      and how much to deposit such that the underlying held by this contract is below
    ///      the underlying dust threshold.
    function newTerm(
        uint256 _mintAmount,
        IVault.JoinPoolRequest calldata request
    ) external onlyAuthorized {
        // First we do a check that we are not in a term
        require(
            lpSupply == 0 && ytSupply == 0,
            "Rollover attempted at wrong time"
        );
        // Next we check that a sufficient time has passed
        require(
            newTermRegistered + minWaitTime < block.timestamp,
            "Rollover before time lock"
        );
        // First register the assets in this address
        impliedBaseSupply = token.balanceOf(address(this));
        // Need to set an allowance on the tranche contract
        token.approve(address(tranche), _mintAmount);
        // Then we mint some amount of principal tokens, this should be calculated by caller
        // to ensure the proper ratio when minting LP.
        tranche.deposit(_mintAmount, address(this));
        // Approve the principal token for deposit on balancer
        tranche.approve(address(balancer), type(uint256).max);
        // Now create the LP token, the caller should have calculated these ahead of time
        // to ensure all underlying token in this address are used.
        balancer.joinPool(
            balancerPoolID,
            address(this),
            address(this),
            request
        );
        // We ensure that all but a dust amount of underlying and PT are used
        // Note - The usage of balanceOf here means that tokens sent to this address directly
        //        should be included in the calculation of the balancer pool join request.
        require(
            token.balanceOf(address(this)) < baseDustThreshold,
            "Manager did not fully rollover base"
        );
        require(
            tranche.balanceOf(address(this)) < baseDustThreshold,
            "Manager did not fully rollover PT"
        );
        // Set the state
        baseSupply = 0;
        ytSupply = uint128(yieldToken.balanceOf(address(this)));
        lpSupply = uint128(balancerPoolAddress.balanceOf(address(this)));
    }

    /// @notice An authorized address can use this to exit the current tranche after it has expired.
    /// @param request A request to the balancer pool calculated and formatted by the authorized address
    ///                Note - This request must remove all LP greater than some dust amount or this will
    ///                revert.
    function exitTerm(IVault.ExitPoolRequest calldata request)
        external
        onlyAuthorized
    {
        // Forward the pool exit request to balancer
        balancer.exitPool(
            balancerPoolID,
            address(this),
            payable(address(this)),
            request
        );
        // Ensure that almost all of the LP was removed
        require(
            balancerPoolAddress.balanceOf(address(this)) < lpDustThreshold,
            "Not enough LP withdrawn"
        );

        // Now redeem the principal tokens
        tranche.withdrawPrincipal(
            tranche.balanceOf(address(this)),
            address(this)
        );
        // Redeem the yield tokens
        tranche.withdrawInterest(
            yieldToken.balanceOf(address(this)),
            address(this)
        );

        // This address should now contain all of the underlying for this asset so we load the balance
        uint256 underlyingBalance = token.balanceOf(address(this));
        // Set the state to new values
        baseSupply = uint128(underlyingBalance);
        lpSupply = 0;
        ytSupply = 0;
    }

    // Governance functions which have the highest level of access control. They are recommended
    // to require a vote from the DAO.

    /// @notice Allows governance to set a new minium settlement time
    /// @param _newMinWaitTime the new minium settlement time in milliseconds.
    function setMinWaitTime(uint256 _newMinWaitTime) external onlyOwner {
        minWaitTime = uint128(_newMinWaitTime);
    }

    /// @notice Allows governance to set a new balancer v2 compatible AMM address.
    /// @param _newBalancer The new AMM address
    function setBalancer(IVault _newBalancer) external onlyOwner {
        balancer = _newBalancer;
        token.approve(address(balancer), type(uint256).max);
    }
}
