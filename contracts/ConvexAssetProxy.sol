// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { WrappedConvexPosition } from "./WrappedConvexPosition.sol";
import "./libraries/Authorizable.sol";
import "./interfaces/external/IConvexBooster.sol";
import "./interfaces/external/IConvexBaseRewardPool.sol";
import "./interfaces/external/ISwapRouter.sol";
import "./interfaces/external/I3CurvePoolDepositZap.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// A little hacky, but solidity complains when trying to import different IERC20 interfaces
interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

/**
 * @title Convex Asset Proxy
 * @notice Proxy for depositing Curve LP shares into Convex's system, and providing a shares based abstraction of ownership
 * @notice Integrating with Curve is quite messy due to non-standard interfaces. Some of the logic below is specific to 3CRV-LUSD
 */
contract ConvexAssetProxy is WrappedConvexPosition, Authorizable {
    using SafeERC20 for IERC20;
    /************************************************
     *  STORAGE
     ***********************************************/
    /// @notice whether this proxy is paused or not
    bool public paused;

    /// @notice % fee keeper collects when calling harvest().
    /// Upper bound is 1000 (i.e 25 would be 2.5% of the total rewards)
    uint256 public keeperFee;

    /// @notice Contains multi-hop Uniswap V3 paths for trading CRV, CVX, & any other reward tokens
    /// index 0 is CRV path, index 1 is CVX path
    bytes[] public swapPaths;

    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/
    /// @notice 3 pool curve zap (deposit contract)
    I3CurvePoolDepositZap public immutable curveZap;

    /// @notice specific pool that the zapper will deposit into under the hood
    address public immutable curveMetaPool;

    /// @notice the pool id (in Convex's system) of the underlying token
    uint256 public immutable pid;

    /// @notice address of the convex Booster contract
    IConvexBooster public immutable booster;

    /// @notice address of the convex rewards contract
    IConvexBaseRewardPool public immutable rewardsContract;

    /// @notice Address of the deposit token 'reciepts' that are given to us
    /// by the booster contract when we deposit the underlying token
    IERC20 public immutable convexDepositToken;

    /// @notice Uniswap V3 router contract
    ISwapRouter public immutable router;

    /// @notice address of CRV, CVX, DAI, USDC, USDT
    IERC20 public constant crv =
        IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 public constant cvx =
        IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant dai =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant usdc =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant usdt =
        IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    /************************************************
     *  EVENTS, STRUCTS, MODIFIERS
     ***********************************************/
    /// @notice emit when pause status changed
    event PauseStatusChanged(bool indexed pauseStatus);

    /// @notice emit when keeper fee changed
    event KeeperFeeChanged(uint256 newFee);

    /// @notice emit when a swap path is changed
    event SwapPathChanged(uint256 indexed index, bytes path);

    /// @notice emit on a harvest
    event Harvested(address harvester, uint256 underlyingHarvested);

    /// @notice emit on a sweep
    event Sweeped(address destination, address[] tokensSweeped);

    /// @notice struct that helps define parameters for a swap
    struct SwapHelper {
        address token; // reward token we are swapping
        uint256 deadline;
        uint256 amountOutMinimum;
    }

    /// @notice helper in constructor to avoid stack too deep
    /**
     * curveZap - address of 3pool Deposit Zap
     * curveMetaPool - underlying curve pool
     * booster address of convex booster for underlying token
     * rewardsContract address of convex rewards contract for underlying token
     * convexDepositToken address of convex deposit token reciept minted by booster
     * router address of Uniswap v3 router
     * pid pool id of the underlying token (in the context of Convex's system)
     * keeperFee the fee that a keeper recieves from calling harvest()
     */
    struct constructorParams {
        I3CurvePoolDepositZap curveZap;
        address curveMetaPool;
        IConvexBooster booster;
        IConvexBaseRewardPool rewardsContract;
        address convexDepositToken;
        ISwapRouter router;
        uint256 pid;
        uint256 keeperFee;
    }

    /**
     * @notice Sets immutables & storage variables
     * @dev we use a struct to pack variables to avoid a stack too deep error
     * @param _constructorParams packing variables to avoid stack error - see struct natspec comments
     * @param _crvSwapPath swap path for CRV token
     * @param _cvxSwapPath swap path for CVX token
     * @param _token The underlying token. This token should revert in the event of a transfer failure
     * @param _name The name of the token (shares) created by this contract
     * @param _symbol The symbol of the token (shares) created by this contract
     * @param _governance Governance address that can perform critical functions
     * @param _pauser Address that can pause this contract
     */
    constructor(
        constructorParams memory _constructorParams,
        bytes memory _crvSwapPath,
        bytes memory _cvxSwapPath,
        address _token,
        string memory _name,
        string memory _symbol,
        address _governance,
        address _pauser
    ) WrappedConvexPosition(_token, _name, _symbol) Authorizable() {
        // Authorize the pauser
        _authorize(_pauser);
        // set the owner
        setOwner(_governance);
        // Set curve zap contract
        curveZap = _constructorParams.curveZap;
        // Set the metapool
        curveMetaPool = _constructorParams.curveMetaPool;
        // Set the booster
        booster = _constructorParams.booster;
        // Set the rewards contract
        rewardsContract = _constructorParams.rewardsContract;
        // Set convexDepositToken
        convexDepositToken = IERC20(_constructorParams.convexDepositToken);
        // Set uni v3 router address
        router = _constructorParams.router;
        // Set the pool id
        pid = _constructorParams.pid;
        // set keeper fee
        keeperFee = _constructorParams.keeperFee;
        // Add the swap paths
        _addSwapPath(_crvSwapPath);
        _addSwapPath(_cvxSwapPath);
        // Approve the booster so it can pull tokens from this address
        IERC20(_token).safeApprove(
            address(_constructorParams.booster),
            type(uint256).max
        );

        // We want our shares decimals to be the same as the convex deposit token decimals
        require(
            decimals ==
                IERC20Decimals(_constructorParams.convexDepositToken)
                    .decimals(),
            "Inconsistent decimals"
        );
    }

    /// @notice Checks that the contract has not been paused
    modifier notPaused() {
        require(!paused, "Paused");
        _;
    }

    /**
     * @notice Deposits underlying token into booster contract & auto stakes the deposit tokens received in the rewardContract
     * @return Tuple (the shares to mint, amount of underlying token deposited)
     */
    function _deposit() internal override notPaused returns (uint256, uint256) {
        // Get the amount deposited
        uint256 amount = token.balanceOf(address(this));

        // // See how many deposit tokens we currently have
        // uint256 depositTokensBefore = rewardsContract.balanceOf(address(this));

        // Shares to be minted = (amount deposited * total shares) / total underlying token controlled by this contract
        // Note that convex deposit receipt tokens and underlying are in a 1:1 relationship
        // i.e for every 1 underlying we deposit we'd be credited with 1 deposit receipt token
        // So we can calculate the total amount deposited in underlying by querying for our balance of deposit receipt token
        uint256 sharesToMint;
        if (totalSupply != 0) {
            sharesToMint =
                (amount * totalSupply) /
                rewardsContract.balanceOf(address(this));
        } else {
            // Reach this case if we have no shares
            sharesToMint = amount;
        }

        // Deposit underlying tokens
        // Last boolean indicates whether we want the Booster to auto-stake our deposit tokens in the reward contract for us
        booster.deposit(pid, amount, true);

        // Return the amount of shares the user has produced, and the amount used for it.
        return (sharesToMint, amount);
    }

    /**
     * @notice Calculates the amount of underlying token out & transfers it to _destination
     * @dev Shares must be burned AFTER this function is called to ensure bookkeeping is correct
     * @param _shares The number of wrapped position shares to withdraw
     * @param _destination The address to send the output funds
     * @return returns the amount of underlying tokens withdrawn
     */
    function _withdraw(
        uint256 _shares,
        address _destination,
        uint256
    ) internal override notPaused returns (uint256) {
        // We need to withdraw from the rewards contract & send to the destination
        // Boolean indicates that we don't want to collect rewards (this saves the user gas)
        uint256 amountUnderlyingToWithdraw = _sharesToUnderlying(_shares);
        rewardsContract.withdrawAndUnwrap(amountUnderlyingToWithdraw, false);

        // Transfer underlying LP tokens to user
        token.transfer(_destination, amountUnderlyingToWithdraw);

        // Return the amount of underlying
        return amountUnderlyingToWithdraw;
    }

    /**
     * @notice Get the underlying amount of tokens per shares given
     * @param _shares The amount of shares you want to know the value of
     * @return Value of shares in underlying token
     */
    function _sharesToUnderlying(uint256 _shares)
        internal
        view
        override
        returns (uint256)
    {
        return (_shares * _pricePerShare()) / (10**decimals);
    }

    /**
     * @notice Get the amount of underlying per share in the vault
     * @return returns the amount of underlying tokens per share
     */
    function _pricePerShare() internal view returns (uint256) {
        // Underlying per share = (1 / total Shares) * total amount of underlying controlled
        return
            ((10**decimals) * rewardsContract.balanceOf(address(this))) /
            totalSupply;
    }

    /**
     * @notice Reset approval for booster contract
     */
    function approve() external {
        // We need to reset to 0 and then approve again
        // see https://curve.readthedocs.io/exchange-lp-tokens.html#CurveToken.approve
        token.approve(address(booster), 0);
        token.approve(address(booster), type(uint256).max);
    }

    /**
     * @notice Allows an authorized address or the owner to pause this contract
     * @param pauseStatus true for paused, false for not paused
     * @dev the caller must be authorized
     */
    function pause(bool pauseStatus) external onlyAuthorized {
        paused = pauseStatus;
        emit PauseStatusChanged(pauseStatus);
    }

    /**
     * @notice sets a new keeper fee, only callable by owner
     * @param newFee the new keeper fee to set
     */
    function setKeeperFee(uint256 newFee) external onlyOwner {
        keeperFee = newFee;
        emit KeeperFeeChanged(newFee);
    }

    /**
     * @notice Add a swap path
     * @param path new path to use for swapping
     */
    function _addSwapPath(bytes memory path) internal {
        // Push dummy path to expand array, then call setPath
        swapPaths.push("");
        _setSwapPath(swapPaths.length - 1, path);
    }

    /**
     * @notice Allows an authorized address to add a swap path
     * @param path new path to use for swapping
     * @dev the caller must be authorized
     */
    function addSwapPath(bytes memory path) external onlyAuthorized {
        _addSwapPath(path);
    }

    /**
     * @notice Allows an authorized address to delete a swap path
     * @dev note we only allow deleting the last path to avoid a gap in our array
     * If a path besides the last path must be deleted, deletePath & addSwapPath will have to be called
     * in an appropriate order
     */
    function deleteSwapPath() external onlyAuthorized {
        delete swapPaths[swapPaths.length - 1];
    }

    /**
     * @notice Sets a new swap path
     * @param index index in swapPaths array to overwrite
     * @param path new path to use for swapping
     */
    function _setSwapPath(uint256 index, bytes memory path) internal {
        // Multihop paths are of the form [tokenA, fee, tokenB, fee, tokenC, ... finalToken]
        // Let's ensure that a compromised authorized address cannot rug
        // by verifying that the input & output tokens are whitelisted (ie output is part of 3CRV pool - DAI, USDC, or USDT)
        address inputToken;
        address outputToken;
        uint256 lengthOfPath = path.length;
        assembly {
            // skip length (first 32 bytes) to load in the next 32 bytes. Now truncate to get only first 20 bytes
            // Address is 20 bytes, and truncates by taking the last 20 bytes of a 32 byte word.
            // So, we shift right by 12 bytes (96 bits)
            inputToken := shr(96, mload(add(path, 0x20)))
            // get the last 20 bytes of path
            // This is skip first 32 bytes, move to end of path array, then move back 20 to start of final outputToken address
            // Truncate to only get first 20 bytes
            outputToken := shr(
                96,
                mload(sub(add(add(path, 0x20), lengthOfPath), 0x14))
            )
        }

        if (index == 0 || index == 1) {
            require(
                inputToken == address(crv) || inputToken == address(cvx),
                "Invalid input token"
            );
        }

        require(
            outputToken == address(dai) ||
                outputToken == address(usdc) ||
                outputToken == address(usdt),
            "Invalid output token"
        );

        // Set the swap path
        swapPaths[index] = path;
        emit SwapPathChanged(index, path);
    }

    /**
     * @notice Allows an authorized address to set the swap path for this contract
     * @param index index in swapPaths array to overwrite
     * @param path new path to use for swapping
     * @dev the caller must be authorized
     */
    function setSwapPath(uint256 index, bytes memory path)
        public
        onlyAuthorized
    {
        _setSwapPath(index, path);
    }

    /**
     * @notice approves curve zap (deposit) contract for all 3 stable coins
     * @dev note that safeApprove requires us to set approval to 0 & then the desired value
     */
    function _approveAll() internal {
        dai.safeApprove(address(curveZap), 0);
        dai.safeApprove(address(curveZap), type(uint256).max);
        usdc.safeApprove(address(curveZap), 0);
        usdc.safeApprove(address(curveZap), type(uint256).max);
        usdt.safeApprove(address(curveZap), 0);
        usdt.safeApprove(address(curveZap), type(uint256).max);
    }

    /**
     * @notice harvest logic to collect rewards in CRV, CVX, etc. The caller will receive a % of rewards (set by keeperFee)
     * @param swapHelpers a list of structs, one for each swap to be made, defining useful parameters
     * @dev keeper will receive all rewards in the underlying token
     * @dev most importantly, each SwapParams should have a reasonable amountOutMinimum to prevent egregious sandwich attacks or frontrunning
     * @dev we must have a swapPaths path for each reward token we wish to swap
     */
    function harvest(SwapHelper[] memory swapHelpers) external onlyAuthorized {
        // Collect our rewards, will also collect extra rewards
        rewardsContract.getReward();

        SwapHelper memory currParamHelper;
        ISwapRouter.ExactInputParams memory params;
        uint256 rewardTokenEarned;

        // Let's swap all the tokens we need to
        for (uint256 i = 0; i < swapHelpers.length; i++) {
            currParamHelper = swapHelpers[i];
            IERC20 rewardToken = IERC20(currParamHelper.token);

            // Check to make sure that this isn't the underlying token or the deposit token
            require(
                address(rewardToken) != address(token) &&
                    address(rewardToken) != address(convexDepositToken),
                "Attempting to swap underlying or deposit token"
            );

            rewardTokenEarned = rewardToken.balanceOf(address(this));
            if (rewardTokenEarned > 0) {
                // Approve router to use our rewardToken
                rewardToken.safeApprove(address(router), rewardTokenEarned);

                // Create params for the swap
                currParamHelper = swapHelpers[i];
                params = ISwapRouter.ExactInputParams({
                    path: swapPaths[i],
                    recipient: address(this),
                    deadline: currParamHelper.deadline,
                    amountIn: rewardTokenEarned,
                    amountOutMinimum: currParamHelper.amountOutMinimum
                });
                router.exactInput(params);
            }
        }

        // First give approval to the curve zap contract to access our stable coins
        _approveAll();
        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 usdtBalance = usdt.balanceOf(address(this));
        curveZap.add_liquidity(
            curveMetaPool,
            [0, daiBalance, usdcBalance, usdtBalance],
            0
        );

        // See how many underlying tokens we received
        uint256 underlyingReceived = token.balanceOf(address(this));
        // Transfer keeper Fee to msg.sender
        // Bounty = (keeper Fee / 1000) * underlying Received
        uint256 bounty = (keeperFee * underlyingReceived) / 1e3;
        token.transfer(msg.sender, bounty);

        // Now stake the newly recieved underlying to the booster contract
        booster.deposit(pid, token.balanceOf(address(this)), true);
        emit Harvested(msg.sender, underlyingReceived);
    }

    /**
     * @notice sweeps this contract to rescue any tokens that we do not handle
     * Could deal with reward tokens we didn't account for, airdropped tokens, etc.
     * @param tokensToSweep array of token address to transfer to destination
     * @param destination the address to send all recovered tokens to
     */
    function sweep(address[] memory tokensToSweep, address destination)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < tokensToSweep.length; i++) {
            IERC20(tokensToSweep[i]).safeTransfer(
                destination,
                IERC20(tokensToSweep[i]).balanceOf(address(this))
            );
        }
        emit Sweeped(destination, tokensToSweep);
    }
}
