// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

contract Purchase {
    uint256 public value;
    uint256 public purchase_ts;
    address payable public seller;
    address payable public buyer;

    enum State {
        Created,
        Locked,
        Completed,
        Inactive
    }
    // The state variable has a default value of the first member, `State.created`
    State public state;

    modifier condition(bool condition_) {
        require(condition_);
        _;
    }

    /// Only the buyer can call this function.
    error OnlyBuyer();
    /// Only the seller can call this function.
    error OnlySeller();
    /// If less than 5 minutes has passed, only buyer can call this function
    error CannotComplete();
    /// The function cannot be called at the current state.
    error InvalidState();
    /// The provided value has to be even.
    error ValueNotEven();

    modifier onlyBuyer() {
        if (msg.sender != buyer) revert OnlyBuyer();
        _;
    }

    modifier onlySeller() {
        if (msg.sender != seller) revert OnlySeller();
        _;
    }

    modifier inState(State state_) {
        if (state != state_) revert InvalidState();
        _;
    }

    modifier canComplete() {
        if (msg.sender != buyer && purchase_ts > block.timestamp - 300) {
            revert CannotComplete();
        }
        _;
    }

    event Aborted();
    event PurchaseConfirmed();
    event ItemReceived();
    event SellerRefunded();

    // Ensure that `msg.value` is an even number.
    // Division will truncate if it is an odd number.
    // Check via multiplication that it wasn't an odd number.
    constructor() payable {
        seller = payable(msg.sender);
        value = msg.value / 2;
        if ((2 * value) != msg.value) revert ValueNotEven();
    }

    /// Abort the purchase and reclaim the ether.
    /// Can only be called by the seller before
    /// the contract is locked.
    function abort() external onlySeller inState(State.Created) {
        emit Aborted();
        state = State.Inactive;
        // We use transfer here directly. It is
        // reentrancy-safe, because it is the
        // last call in this function and we
        // already changed the state.
        seller.transfer(address(this).balance);
    }

    /// Confirm the purchase as buyer.
    /// Transaction has to include `2 * value` ether.
    /// The ether will be locked until confirmReceived
    /// is called.
    function confirmPurchase()
        external
        payable
        inState(State.Created)
        condition(msg.value == (2 * value))
    {
        emit PurchaseConfirmed();
        buyer = payable(msg.sender);
        state = State.Locked;
        purchase_ts = block.timestamp;
    }

    /// If called by the buyer, confirms that has received the item and releases the locked ether
    /// The seller can call the function if 5 minutes have passed and the buyer has not confirmed
    /// to get refunded and send funds back to the buyer
    function completePurchase() external canComplete inState(State.Locked) {
        if (msg.sender == buyer) {
            emit ItemReceived();
        }

        emit SellerRefunded();

        // It is important to change the state first because
        // otherwise, the contracts called using `send` below
        // can call in again here.
        state = State.Completed;

        buyer.transfer(value);
        seller.transfer(3 * value);
    }
}
