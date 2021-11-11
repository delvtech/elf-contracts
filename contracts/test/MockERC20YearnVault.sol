pragma solidity ^0.8.0;
import "../interfaces/IYearnVault.sol";
import "../libraries/Authorizable.sol";
import "../libraries/ERC20Permit.sol";

contract MockERC20YearnVault is IYearnVault, Authorizable, ERC20Permit {
    // total amount of vault shares in existence
    uint256 public totalShares;

    // a large number used to offset potential division precision errors
    uint256 public precisionFactor;

    // underlying token
    ERC20Permit public token;

    // variables for the profit time-lock
    uint256 public constant DEGRADATION_COEFFICIENT = 1e18;
    uint256 public lockedProfitDegradation;

    // last time someone deposited value through report()
    uint256 public lastReport;
    // the amount of tokens locked after a report()
    uint256 public lockedProfit;

    /**
    @param _token The ERC20 token the vault accepts
     */
    constructor(address _token)
        Authorizable()
        ERC20Permit("Mock Yearn Vault", "MYV")
    {
        _authorize(msg.sender);
        token = ERC20Permit(_token);
        decimals = token.decimals();
        precisionFactor = 10**(18 - decimals);
        // 6 hours in blocks
        // 6*60*60 ~= 1e6 / 46
        lockedProfitDegradation = (DEGRADATION_COEFFICIENT * 46) / 1e6;
    }

    function apiVersion() external pure override returns (string memory) {
        return ("0.3.2");
    }

    /**
    @notice Add tokens to the vault. Increases totalAssets.
    @param _deposit The amount of tokens to deposit
    @dev There is no logic to rebalance lockedAmount.
    Repeat calls will just reset it.
    */
    function report(uint256 _deposit) external onlyAuthorized {
        lastReport = block.timestamp;
        // mock vault does not take performance or management fee
        // so the full deposit is locked profit.
        lockedProfit = _deposit;
        token.transferFrom(msg.sender, address(this), _deposit);
    }

    /**
    @notice Deposit `_amount` of tokens into the yearn vault. 
    `_recipient` receives shares.
    @param _amount The amount of underlying tokens to deposit.
    @param _recipient The recipient of the vault shares.
    @return The vault shares received.

     */
    function deposit(uint256 _amount, address _recipient)
        external
        override
        returns (uint256)
    {
        require(_amount > 0, "depositing 0 value");
        uint256 shares = _issueSharesForAmount(_recipient, _amount);
        token.transferFrom(msg.sender, address(this), _amount);
        return shares;
    }

    /**
    @notice Withdraw `_maxShares` of shares from caller `_recipient`
    receives underlying tokens.
    @param _maxShares The amount of shares to redeem for underlying.
    @param _recipient The recipient of the underlying tokens.
    @param _maxLoss The max permitted withdrawal loss. (1 = 0.01%, 10000 = 100%).
    @return The amount of underlying tokens that were redeemed from _maxShares shares.
     */
    function withdraw(
        uint256 _maxShares,
        address _recipient,
        uint256 _maxLoss
    ) external override returns (uint256) {
        require(_maxShares > 0, "Can't withdraw zero");
        require(balanceOf[msg.sender] >= _maxShares, "Shares exceed balance");
        uint256 value = _shareValue(_maxShares);

        totalShares -= _maxShares;
        balanceOf[msg.sender] -= _maxShares;

        token.transfer(_recipient, value);
        return value;
    }

    /**
    @notice Returns the amount of underlying per each unit [10^decimals] of yearn shares
     */
    function pricePerShare() public view override returns (uint256) {
        return _shareValue(10**decimals);
    }

    /**
    @notice Get the governance address. It will be address(0)
    it is not used for this mock.
     */
    function governance() public view override returns (address) {
        return address(0);
    }

    /**
    @notice The deposit limit for this vault.
    @dev Can only be unlimited for this mock.
     */
    function setDepositLimit(uint256 _limit) public override {
        require(msg.sender == governance(), "!governance");
    }

    /**
    @notice Returns total assets held by the contract.
    @dev This is a mock and there is no debt. The total assets are just the
    underlying tokens held by the contract.
     */
    function totalAssets() public view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
    @param _to The address to receive the shares.
    @param _amount The amount of underlying tokens to convert to shares.
    @return The amount of shares _amount yields.
     */
    function _issueSharesForAmount(address _to, uint256 _amount)
        internal
        returns (uint256)
    {
        uint256 shares;
        if (totalShares > 0) {
            shares =
                (precisionFactor * _amount * totalShares) /
                totalAssets() /
                precisionFactor;
        } else {
            shares = _amount;
        }
        totalShares += shares;
        balanceOf[_to] += shares;
        return shares;
    }

    /**
    @notice Return the amount of underlying tokens an amount of `_shares`
    is worth at any given time. 
    @param _shares The amount of shares to check.
    @return The amount of underlying tokens the `_shares` can be redeemed for.
     */
    function _shareValue(uint256 _shares) internal view returns (uint256) {
        if (totalShares == 0) {
            return _shares;
        }
        // determine the current value of the shares
        uint256 lockedFundsRatio = (block.timestamp - lastReport) *
            lockedProfitDegradation;
        uint256 freeFunds = totalAssets();
        if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
            freeFunds -= (lockedProfit -
                ((precisionFactor * lockedFundsRatio * lockedProfit) /
                    DEGRADATION_COEFFICIENT /
                    precisionFactor));
        }
        return ((precisionFactor * _shares * freeFunds) /
            totalShares /
            precisionFactor);
    }

    /**
    @notice Get the total number of vault shares.
    @return Total vault shares.
     */
    function totalSupply() external view override returns (uint256) {
        return totalShares;
    }
}
