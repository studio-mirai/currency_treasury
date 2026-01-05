// Copyright (c) Studio Mirai, LLC
// SPDX-License-Identifier: Apache-2.0

module currency_treasury::mint_facility;

use sui::balance::{Self, Balance};
use sui::derived_object::claim;
use sui::event::emit;

//=== Structs ===

public struct MintFacility<phantom Currency, phantom Authority: drop> has key, store {
    id: UID,
    number: u64,
    balance: Balance<Currency>,
    total_capacity: u64,
    refresh_epoch: u64,
}

public struct MintFacilityKey<phantom Authority: drop>(u64) has copy, drop, store;

/// A transferable claim object that allows a user to redeem funds from the MintFacility
/// at a future time. This reduces shared object congestion by decoupling the issuance
/// of withdrawal rights from the actual withdrawal transaction.
///
/// Flow:
/// 1. Authority calls `new_mint_option()` - creates this object with only READ access to MintFacility
/// 2. User holds the MintOption (transferable owned object)
/// 3. User calls `redeem_mint_option()` - redeems when convenient (requires WRITE access)
///
/// This pattern prevents transaction congestion on `withdraw()` by allowing issuance
/// of withdrawal rights without immediate shared object mutation. Users can redeem
/// their options asynchronously, spreading out shared object write contention.
public struct MintOption<phantom Currency, phantom Authority: drop> has key, store {
    id: UID,
    value: u64,
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

public struct MintOptionIssuedEvent<
    phantom Currency,
    phantom Authority: drop,
> has copy, drop, store {
    facility_id: ID,
    value: u64,
}

public struct MintOptionRedeemedEvent<
    phantom Currency,
    phantom Authority: drop,
> has copy, drop, store {
    facility_id: ID,
    value: u64,
}

//=== Public Functions ===

public fun new_mint_option<Currency, Authority: drop>(
    self: &MintFacility<Currency, Authority>,
    _: Authority,
    value: u64,
    ctx: &mut TxContext,
): MintOption<Currency, Authority> {
    emit(MintOptionIssuedEvent<Currency, Authority> {
        facility_id: self.id(),
        value,
    });

    MintOption {
        id: object::new(ctx),
        value,
    }
}

public fun redeem_mint_option<Currency, Authority: drop>(
    self: &mut MintFacility<Currency, Authority>,
    mint_option: MintOption<Currency, Authority>,
): Balance<Currency> {
    assert!(self.balance.value() >= mint_option.value, EInsufficientBalance);

    let MintOption { id, value } = mint_option;
    id.delete();

    emit(MintOptionRedeemedEvent<Currency, Authority> {
        facility_id: self.id(),
        value,
    });

    self.balance.split(value)
}

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
    parent: &mut UID,
    number: u64,
): MintFacility<Currency, Authority> {
    MintFacility {
        id: claim(parent, MintFacilityKey<Authority>(number)),
        number,
        balance: balance::zero(),
        total_capacity: 0,
        refresh_epoch: 0,
    }
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
