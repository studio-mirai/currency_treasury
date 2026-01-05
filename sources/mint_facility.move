// Copyright (c) Studio Mirai, LLC
// SPDX-License-Identifier: Apache-2.0

module currency_treasury::mint_facility;

use sui::balance::{Self, Balance};
use sui::derived_object::{claim, exists};
use sui::event::emit;

//=== Structs ===

public struct MintFacility<phantom Currency, phantom Authority: drop> has key, store {
    id: UID,
    balance: Balance<Currency>,
    total_capacity: u64,
    refresh_epoch: u64,
}

//=== Errors ===

const EInsufficientBalance: u64 = 0;
const ERefreshEpochNotReached: u64 = 1;
const EInsufficientCapacity: u64 = 2;

//=== Events ===

public struct CurrencyDepositEvent<
    phantom Currency,
    phantom Authority: drop,
> has copy, drop, store {
    facility_id: ID,
    value: u64,
}

public struct CurrencyWithdrawalEvent<
    phantom Currency,
    phantom Authority: drop,
> has copy, drop, store {
    facility_id: ID,
    value: u64,
}

//=== Public Functions ===

public fun withdraw<Currency, Authority: drop>(
    self: &mut MintFacility<Currency, Authority>,
    _: Authority,
    value: u64,
): Balance<Currency> {
    assert!(self.balance.value() >= value, EInsufficientBalance);

    emit(CurrencyWithdrawalEvent<Currency, Authority> {
        facility_id: self.id(),
        value,
    });

    self.balance.split(value)
}

//=== Package Functions ===

public(package) fun new<Currency, Authority: drop>(
    ctx: &mut TxContext,
): MintFacility<Currency, Authority> {
    MintFacility {
        id: object::new(ctx),
        balance: balance::zero(),
        total_capacity: 0,
        refresh_epoch: 0,
    }
}

public(package) fun destroy<Currency, Authority: drop>(
    self: MintFacility<Currency, Authority>,
): (ID, Balance<Currency>) {
    let MintFacility { id, balance, .. } = self;
    let mint_facility_id = id.to_inner();
    id.delete();

    (mint_facility_id, balance)
}

public(package) fun deposit<Currency, Authority: drop>(
    self: &mut MintFacility<Currency, Authority>,
    balance: Balance<Currency>,
    ctx: &TxContext,
) {
    assert!(ctx.epoch() >= self.refresh_epoch, ERefreshEpochNotReached);
    assert!(self.balance.value() + balance.value() <= self.total_capacity, EInsufficientCapacity);

    emit(CurrencyDepositEvent<Currency, Authority> {
        facility_id: self.id(),
        value: balance.value(),
    });

    self.balance.join(balance);
    self.refresh_epoch = ctx.epoch() + 1;
}

//=== Public View Functions ===

public fun id<Currency, Authority: drop>(self: &MintFacility<Currency, Authority>): ID {
    self.id.to_inner()
}

public fun balance<Currency, Authority: drop>(
    self: &MintFacility<Currency, Authority>,
): &Balance<Currency> {
    &self.balance
}

public fun total_capacity<Currency, Authority: drop>(
    self: &MintFacility<Currency, Authority>,
): u64 {
    self.total_capacity
}

public fun available_capacity<Currency, Authority: drop>(
    self: &MintFacility<Currency, Authority>,
): u64 {
    self.total_capacity - self.balance.value()
}

public fun refresh_epoch<Currency, Authority: drop>(self: &MintFacility<Currency, Authority>): u64 {
    self.refresh_epoch
}

//=== Assert Functions ===

public fun assert_can_deposit<Currency, Authority: drop>(
    self: &MintFacility<Currency, Authority>,
    value: u64,
    ctx: &TxContext,
) {
    assert!(ctx.epoch() >= self.refresh_epoch, ERefreshEpochNotReached);
    assert!(self.available_capacity() >= value, EInsufficientCapacity);
}
