// Copyright (c) Studio Mirai, LLC
// SPDX-License-Identifier: Apache-2.0

/**
 * CurrencyTreasury is a TreasuryCap wrapper that exposes common treasury-related operations.
 */
module currency_treasury::currency_treasury;

use currency_treasury::burn_facility::{Self, BurnFacility};
use currency_treasury::mint_facility::{Self, MintFacility};
use std::type_name::{TypeName, with_defining_ids};
use sui::coin::TreasuryCap;
use sui::event::emit;
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};

//=== Structs ===

public struct CurrencyTreasury<phantom Currency> has key, store {
    id: UID,
    treasury_cap: TreasuryCap<Currency>,
    mint_facilities: Table<TypeName, VecSet<ID>>,
}

public struct CurrencyTreasuryAdminCap<phantom Currency> has key, store {
    id: UID,
}

//=== Events ===

public struct CurrencyTreasuryCreatedEvent<phantom Currency> has copy, drop, store {
    treasury_id: ID,
}

public struct CurrencyTreasuryDestroyedEvent<phantom Currency> has copy, drop, store {
    treasury_id: ID,
}

public struct CurrencyMintedEvent<phantom Currency> has copy, drop, store {
    treasury_id: ID,
    facility_id: ID,
    value: u64,
}

public struct CurrencyBurnedEvent<phantom Currency> has copy, drop, store {
    treasury_id: ID,
    facility_id: ID,
    value: u64,
}

//=== Constants ===

const MAX_FACILITIES_PER_AUTHORITY: u64 = 500;

//=== Errors ===

const EMintFacilitiesNotEmpty: u64 = 0;
const EMaxFacilitiesReached: u64 = 1;

//=== Public Functions ===

public fun new<Currency>(
    treasury_cap: TreasuryCap<Currency>,
    ctx: &mut TxContext,
): (CurrencyTreasury<Currency>, CurrencyTreasuryAdminCap<Currency>, BurnFacility<Currency>) {
    let mut currency_treasury = CurrencyTreasury {
        id: object::new(ctx),
        treasury_cap: treasury_cap,
        mint_facilities: table::new(ctx),
    };

    let currency_treasury_admin_cap = CurrencyTreasuryAdminCap {
        id: object::new(ctx),
    };

    let burn_facility = burn_facility::new(&mut currency_treasury.id);

    emit(CurrencyTreasuryCreatedEvent<Currency> {
        treasury_id: currency_treasury.id(),
    });

    (currency_treasury, currency_treasury_admin_cap, burn_facility)
}

public fun new_mint_facility<Currency, Authority: drop>(
    self: &mut CurrencyTreasury<Currency>,
    _: &CurrencyTreasuryAdminCap<Currency>,
    ctx: &mut TxContext,
): MintFacility<Currency, Authority> {
    let authority_type = with_defining_ids<Authority>();

    let mint_facility = mint_facility::new<Currency, Authority>(ctx);

    if (!self.mint_facilities.contains(authority_type)) {
        self.mint_facilities.add(authority_type, vec_set::singleton(mint_facility.id()));
    } else {
        let mint_facilities = self.mint_facilities.borrow_mut(authority_type);
        assert!(mint_facilities.length() < MAX_FACILITIES_PER_AUTHORITY, EMaxFacilitiesReached);
        mint_facilities.insert(mint_facility.id());
    };

    mint_facility
}

public fun destroy_mint_facility<Currency, Authority: drop>(
    self: &mut CurrencyTreasury<Currency>,
    _: &CurrencyTreasuryAdminCap<Currency>,
    mint_facility: MintFacility<Currency, Authority>,
) {
    // Destroy the mint
    let (mint_facility_id, remaining_balance) = mint_facility.destroy();

    // If there's a 
    if (remaining_balance.value() > 0) {
        self.treasury_cap.supply_mut().decrease_supply(remaining_balance);
    } else {
        remaining_balance.destroy_zero();
    };

    self.mint_facilities.borrow_mut(with_defining_ids<Authority>()).remove(&mint_facility_id);
}

public fun mint<Currency, Authority: drop>(
    self: &mut CurrencyTreasury<Currency>,
    _: &CurrencyTreasuryAdminCap<Currency>,
    mint_facility: &mut MintFacility<Currency, Authority>,
    value: Option<u64>,
    ctx: &TxContext,
) {
    let value = value.destroy_or!(mint_facility.available_capacity());
    mint_facility.assert_can_deposit(value, ctx);
    let balance = self.treasury_cap.mint_balance(value);
    mint_facility.deposit(balance, ctx);

    emit(CurrencyMintedEvent<Currency> {
        treasury_id: self.id(),
        facility_id: mint_facility.id(),
        value,
    });
}

public fun burn<Currency>(
    self: &mut CurrencyTreasury<Currency>,
    _: &CurrencyTreasuryAdminCap<Currency>,
    burn_facility: &mut BurnFacility<Currency>,
    value: Option<u64>,
) {
    let balance = burn_facility.withdraw(value);

    emit(CurrencyBurnedEvent<Currency> {
        treasury_id: self.id(),
        facility_id: burn_facility.id(),
        value: balance.value(),
    });

    self.treasury_cap.supply_mut().decrease_supply(balance);
}

public fun destroy<Currency>(
    self: CurrencyTreasury<Currency>,
    cap: CurrencyTreasuryAdminCap<Currency>,
): TreasuryCap<Currency> {
    assert!(self.mint_facilities.is_empty(), EMintFacilitiesNotEmpty);

    let CurrencyTreasury { id, treasury_cap, mint_facilities } = self;
    mint_facilities.destroy_empty();

    emit(CurrencyTreasuryDestroyedEvent<Currency> {
        treasury_id: id.to_inner(),
    });

    id.delete();

    let CurrencyTreasuryAdminCap { id } = cap;
    id.delete();

    treasury_cap
}

//=== Public View Functions ===

public fun id<Currency>(self: &CurrencyTreasury<Currency>): ID {
    self.id.to_inner()
}
