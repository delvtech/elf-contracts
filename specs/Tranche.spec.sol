/*
 * `num` ranges over non-negative real numbers.
 */

spec Tranche {
    Position position; // many tranches can be associated with the same position
    Token token;

    mapping(address => num) pt; // principal tokens // code.Tranche.balanceOf
    mapping(address => num) it; // interest tokens // code.InterestToken.balanceOf

    /* until expiration, we have:
     * - forall x, pt[x] >= it[x]
     * - sum(it) is equal to the total deposits
     */

    // deposit underlying tokens
    function deposit(num amount, address owner) {
        require(!hasLoss(BUY)); // TODO: it is possible !hasLoss(BUY) && hasLoss(SELL). Is this still safe in that case?

        num deduction = amount * yieldRate(BUY);
        require(deduction <= amount); // NOTE: `deduction` could be bigger than `amount` when the yield rate is more than 100%.

        token.transferFrom(owner, this, amount);
        num share = position.deposit(amount);
        // assert(vault.buyPrice() == amount / share);

        pt[owner] += amount - deduction; // no underflow
        it[owner] += amount;
    }

    // redeem principal tokens
    function withdrawPrincipal(num amount, address owner) {
        num redemptionAmount = amount;
        if (hasLoss(SELL)) {
            redemptionAmount = totalValue(SELL) * amount / sum(pt);
        }

        require(pt[owner] >= amount);
        pt[owner] -= amount; // no underflow

        num share = position.withdraw(redemptionAmount);
        // assert(vault.sellPrice() == redemptionAmount / share);
        token.transferFrom(this, owner, redemptionAmount);
    }

    // redeem interest tokens
    function withdrawInterest(num amount, address owner) {
        num redemptionAmount = amount * yieldRate(SELL);

        require(it[owner] >= amount);
        it[owner] -= amount; // no underflow

        num share = position.withdraw(redemptionAmount);
        // assert(vault.sellPrice() == redemptionAmount / share);
        token.transferFrom(this, owner, redemptionAmount);
    }

    // @inv totalValue(BUY) >= totalValue(SELL)
    function totalValue(mode) view {
        return position.value(this, mode);
    }

    // yield per interest token
    // @inv yieldRate(BUY) >= yieldRate(SELL)
    function yieldRate(mode) view {
        if (hasLoss(mode)) return 0;

        num currentYield = totalValue(mode) - sum(pt); // no underflow
        return currentYield / sum(it); // NOTE: this could be bigger than 1, if the value becomes more than double.
    }

    // loss in principal
    // @inv hasLoss(BUY) implies hasLoss(SELL)
    function hasLoss(mode) view {
        return totalValue(mode) < sum(pt);
    }
}

spec Position {
    Vault vault; // many positions can be associated with the same vault
    Token token;

    mapping(address => num) shares; // position shares // code.WrappedPosition.balanceOf

    num reserveUnderlying;
    num reserveShares;
    mapping(address => num) reserveBalances;

    /*
     * @inv token.balanceOf(this) >= reserveUnderlying
     * @inv vault.shares[this] == reserveShares + sum(shares)
     */

    function value(address owner, mode) view {
        num price = vault.sharePrice();
        if (mode == BUY) price = vault.buyPrice();
        if (mode == SELL) price = vault.sellPrice();
        return shares[owner] * price;
    }

    // deposit underlying
    function deposit(num amount) {
        num share = amount / vault.buyPrice();
        token.transferFrom(msg.sender, this, amount);

        /* no reserve version:
        num cost = vault.buy(share); // assert(cost == amount);
        */
        reserveUnderlying += amount;
        if (reserveShares < share) buyReserve();
        // assert(reserveShares >= share);
        reserveShares -= share; // no underflow

        shares[msg.sender] += share;
        return share;
    }

    // withdraw underlying
    function withdraw(num amount) { // code.WrappedPosition.withdrawUnderlying()
        num share = amount / vault.sellPrice();
        require(shares[msg.sender] >= share);
        shares[msg.sender] -= share; // no underflow

        /* no reserve version:
        num proceeds = vault.sell(share); // assert(proceeds == amount);
        */
        reserveShares += share;
        if (reserveUnderlying < amount) sellReserve();
        // assert(reserveUnderlying >= amount);
        reserveUnderlying -= amount; // no underflow

        token.transferFrom(this, msg.sender, amount);
        return share;
    }

    // @inv old(token.balanceOf(this) - reserveUnderlying) == new(token.balanceOf(this) - reserveUnderlying)
    function buyReserve() {
        num share = reserveUnderlying / buyPrice();
        num cost = vault.buy(share);
        // assert(vault.buyPrice() == cost / share);
        reserveUnderlying = 0;
        reserveShares += share;
    }

    // @inv old(token.balanceOf(this) - reserveUnderlying) == new(token.balanceOf(this) - reserveUnderlying)
    function sellReserve() {
        num proceeds = vault.sell(reserveShares);
        // assert(vault.sellPrice() == proceeds / reserveShares);
        reserveShares = 0;
        reserveUnderlying += proceeds;
    }

    /*
     * @inv sum(reserveBalances) == 0 => reserveUnderlying == reserveShares == 0
     * @inv old(reservePrice()) <= new(reservePrice()) // NOTE: == instead of <=, if sellPrice() is used in reserveDeposit().
     */

    function reserveDeposit(num amount) {
        token.transferFrom(msg.sender, this, amount);

        num total = reserveUnderlying + reserveShares * vault.buyPrice(); // TODO: buyPrice() or sellPrice()?
        num mint = sum(reserveBalances) * amount / total;
        if (sum(reserveBalances) == 0) mint = amount;
        reserveBalances[msg.sender] += mint;

        reserveUnderlying += amount;
    }

    // @inv old(reservePrice()) == new(reservePrice())
    function reserveWithdraw(num burn) {
        num frac = burn / sum(reserveBalances);
        require(reserveBalances[msg.sender] >= burn);
        reserveBalances[msg.sender] -= burn; // no underflow

        num userUnderlying = reserveUnderlying * frac;
        num userShares = reserveShares * frac;
        num freedUnderlying = vault.sell(userShares);
        // assert(vault.sellPrice() == freedUnderlying / userShares);

        // assert(frac <= 1);
        reserveUnderlying -= userUnderlying; // no underflow
        reserveShares -= userShares; // no underflow
        token.transferFrom(this, msg.sender, userUnderlying + freedUnderlying);
    }

    function reservePrice() view {
        return (reserveUnderlying + reserveShares * vault.sellPrice()) / sum(reserveBalances);
    }
}

interface Vault {
    Token token; // underlying asset

    mapping(address => num) shares; // vault shares

    // total valuation of underlying assets
    function totalAssets() returns (num);

    // tokens per share
    function sharePrice() {
        return totalAssets() / sum(shares);
    }

    // tokens per share when buying shares
    function buyPrice() returns (num);

    // tokens per share when selling shares
    function sellPrice() returns (num); // code.Vault.pricePerShare()

    /*
     * @inv sharePrice() >= buyPrice() >= sellPrice()
     */

    /*
     * In Yearn v0.3.x: @inv sharePrice() == buyPrice() >= sellPrice()
     * In Yearn v0.4.x: @inv sharePrice() >= buyPrice() == sellPrice()
     */

    // buy shares
    function buy(num share) { // code.Vault.deposit() but different interface
        num cost = share * buyPrice();
        token.transferFrom(msg.sender, this, cost);
        shares[msg.sender] += share;
        return cost;
    }

    // sell shares
    function sell(num share) { // code.Vault.withdraw()
        num proceeds = share * sellPrice();
        require(shares[msg.sender] >= share);
        shares[msg.sender] -= share; // no underflow
        token.transferFrom(this, msg.sender, proceeds);
        return proceeds;
    }
}
