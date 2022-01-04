// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./ConditionalEscrowUpgradeable.sol";
import "../../proxy/Initializable.sol";

/**
 * @title RefundEscrow
 * @dev Escrow that holds funds for a beneficiary, deposited from multiple
 * parties.
 * @dev Intended usage: See {Escrow}. Same usage guidelines apply here.
 * @dev The owner account (that is, the contract that instantiates this
 * contract) may deposit, close the deposit period, and allow for either
 * withdrawal by the beneficiary, or refunds to the depositors. All interactions
 * with `RefundEscrow` will be made through the owner contract.
 */
contract RefundEscrowUpgradeable is
    Initializable,
    ConditionalEscrowUpgradeable
{
    enum State {Active, Refunding, Closed}

    event RefundsClosed();
    event RefundsEnabled();

    State private _state;
    address payable private _beneficiary;

    /**
     * @dev Constructor.
     * @param beneficiary The beneficiary of the deposits.
     */
    function __RefundEscrow_init(address payable beneficiary)
        internal
        initializer
    {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Escrow_init_unchained();
        __ConditionalEscrow_init_unchained();
        __RefundEscrow_init_unchained(beneficiary);
    }

    function __RefundEscrow_init_unchained(address payable beneficiary)
        internal
        initializer
    {
        require(
            beneficiary != address(0),
            "RefundEscrow: beneficiary is the zero address"
        );
        _beneficiary = beneficiary;
        _state = State.Active;
    }

    /**
     * @return The current state of the escrow.
     */
    function state() public view returns (State) {
        return _state;
    }

    /**
     * @return The beneficiary of the escrow.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @dev Stores funds that may later be refunded.
     * @param refundee The address funds will be sent to if a refund occurs.
     */
    function deposit(address refundee) public virtual override payable {
        require(
            _state == State.Active,
            "RefundEscrow: can only deposit while active"
        );
        super.deposit(refundee);
    }

    /**
     * @dev Allows for the beneficiary to withdraw their funds, rejecting
     * further deposits.
     */
    function close() public virtual onlyOwner {
        require(
            _state == State.Active,
            "RefundEscrow: can only close while active"
        );
        _state = State.Closed;
        emit RefundsClosed();
    }

    /**
     * @dev Allows for refunds to take place, rejecting further deposits.
     */
    function enableRefunds() public virtual onlyOwner {
        require(
            _state == State.Active,
            "RefundEscrow: can only enable refunds while active"
        );
        _state = State.Refunding;
        emit RefundsEnabled();
    }

    /**
     * @dev Withdraws the beneficiary's funds.
     */
    function beneficiaryWithdraw() public virtual {
        require(
            _state == State.Closed,
            "RefundEscrow: beneficiary can only withdraw while closed"
        );
        _beneficiary.transfer(address(this).balance);
    }

    /**
     * @dev Returns whether refundees can withdraw their deposits (be refunded). The overridden function receives a
     * 'payee' argument, but we ignore it here since the condition is global, not per-payee.
     */
    function withdrawalAllowed(address) public override view returns (bool) {
        return _state == State.Refunding;
    }

    uint256[49] private __gap;
}
