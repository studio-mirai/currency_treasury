// Copyright (c) Studio Mirai, LLC
// SPDX-License-Identifier: Apache-2.0

/**
 * CurrencyTreasury is a TreasuryCap wrapper that exposes common treasury-related operations.
 */
module currency_treasury::currency_treasury;

use currency_treasury::burn_facility::{Self, BurnFacility};
use currency_treasury::mint_facility::MintFacility;
use sui::coin::TreasuryCap;
use sui::event::emit;

//=== Structs ===

public struct CurrencyTreasury<phantom Currency> has key, store {
    id: UID,
    treasury_cap: TreasuryCap<Currency>,
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

//=== Public Functions ===

public fun new<Currency>(
    treasury_cap: TreasuryCap<Currency>,
    ctx: &mut TxContext,
): (CurrencyTreasury<Currency>, CurrencyTreasuryAdminCap<Currency>, BurnFacility<Currency>) {
    let mut currency_treasury = CurrencyTreasury {
        id: object::new(ctx),
        treasury_cap: treasury_cap,
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
    let CurrencyTreasury { id, treasury_cap } = self;

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
