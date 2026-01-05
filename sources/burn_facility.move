// Copyright (c) Studio Mirai, LLC
// SPDX-License-Identifier: Apache-2.0

// TODO: Add redeem_and_deposit once balance accumulators are live.

module currency_treasury::burn_facility;

use sui::balance::{Self, Balance};
use sui::coin::Coin;
use sui::derived_object::{claim, derive_address};
use sui::transfer::Receiving;

//=== Structs ===

public struct BurnFacility<phantom Currency> has key, store {
    id: UID,
    balance: Balance<Currency>,
}

public struct BurnFacilityKey() has copy, drop, store;

//=== Errors ===

const ENoCoinsToReceive: u64 = 0;

//=== Public Functions ===

public fun deposit<Currency>(self: &mut BurnFacility<Currency>, balance: Balance<Currency>) {
    self.balance.join(balance);
}

public fun receive_and_deposit<Currency>(
    self: &mut BurnFacility<Currency>,
    coins_to_receive: vector<Receiving<Coin<Currency>>>,
) {
    assert!(!coins_to_receive.is_empty(), ENoCoinsToReceive);

    coins_to_receive.destroy!(|coin_to_receive| {
        let balance = transfer::public_receive(&mut self.id, coin_to_receive).into_balance();

        if (balance.value() > 0) {
            self.balance.join(balance);
        } else {
            balance.destroy_zero();
        }
    });
}

//=== Package Functions ===

public(package) fun new<Currency>(parent: &mut UID): BurnFacility<Currency> {
    BurnFacility {
        id: claim(parent, BurnFacilityKey()),
        balance: balance::zero(),
    }
}

public(package) fun balance_mut<Currency>(
    self: &mut BurnFacility<Currency>,
): &mut Balance<Currency> {
    &mut self.balance
}

public(package) fun withdraw<Currency>(
    self: &mut BurnFacility<Currency>,
    value: Option<u64>,
): Balance<Currency> {
    let value = value.destroy_or!(self.balance.value());
    self.balance.split(value)
}

//=== Public View Functions ===

public fun id<Currency>(self: &BurnFacility<Currency>): ID {
    self.id.to_inner()
}

public fun derived_address(parent: ID): address {
    derive_address(parent, BurnFacilityKey())
}
