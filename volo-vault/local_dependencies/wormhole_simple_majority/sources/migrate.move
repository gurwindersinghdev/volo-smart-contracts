// SPDX-License-Identifier: Apache 2

/// This module implements a public method intended to be called after an
/// upgrade has been committed. The purpose is to add one-off migration logic
/// that would alter Wormhole `State`.
///
/// Included in migration is the ability to ensure that breaking changes for
/// any of Wormhole's methods by enforcing the current build version as their
/// required minimum version.
module wormhole_simple_majority::migrate {
    use sui::clock::{Clock};
    use sui::object::{ID};

    use wormhole_simple_majority::governance_message::{Self};
    use wormhole_simple_majority::state::{Self, State};
    use wormhole_simple_majority::upgrade_contract::{Self};
    use wormhole_simple_majority::vaa::{Self};

    /// Event reflecting when `migrate` is successfully executed.
    struct MigrateComplete has drop, copy {
        package: ID
    }

    /// Execute migration logic. See `wormhole_simple_majority::migrate` description for more
    /// info.
    public fun migrate(
        wormhole_state: &mut State,
        upgrade_vaa_buf: vector<u8>,
        the_clock: &Clock
    ) {
        state::migrate__v__0_2_0(wormhole_state);

        // Perform standard migrate.
        handle_migrate(wormhole_state, upgrade_vaa_buf, the_clock);

        ////////////////////////////////////////////////////////////////////////
        //
        // NOTE: Put any one-off migration logic here.
        //
        // Most upgrades likely won't need to do anything, in which case the
        // rest of this function's body may be empty. Make sure to delete it
        // after the migration has gone through successfully.
        //
        // WARNING: The migration does *not* proceed atomically with the
        // upgrade (as they are done in separate transactions).
        // If the nature of this migration absolutely requires the migration to
        // happen before certain other functionality is available, then guard
        // that functionality with the `assert!` from above.
        //
        ////////////////////////////////////////////////////////////////////////

        ////////////////////////////////////////////////////////////////////////
    }

    fun handle_migrate(
        wormhole_state: &mut State,
        upgrade_vaa_buf: vector<u8>,
        the_clock: &Clock
    ) {
        // Update the version first.
        //
        // See `version_control` module for hard-coded configuration.
        state::migrate_version(wormhole_state);

        // This VAA needs to have been used for upgrading this package.
        //
        // NOTE: All of the following methods have protections to make sure that
        // the current build is used. Given that we officially migrated the
        // version as the first call of `migrate`, these should be successful.

        // First we need to check that `parse_and_verify` still works.
        let verified_vaa =
            vaa::parse_and_verify(wormhole_state, upgrade_vaa_buf, the_clock);

        // And governance methods.
        let ticket = upgrade_contract::authorize_governance(wormhole_state);
        let receipt =
            governance_message::verify_vaa(
                wormhole_state,
                verified_vaa,
                ticket
            );

        // This capability ensures that the current build version is used.
        let latest_only = state::assert_latest_only(wormhole_state);

        // Check if build digest is the current one.
        let digest =
            upgrade_contract::take_digest(
                governance_message::payload(&receipt)
            );
        state::assert_authorized_digest(&latest_only, wormhole_state, digest);
        governance_message::destroy(receipt);

        // Finally emit an event reflecting a successful migrate.
        let package = state::current_package(&latest_only, wormhole_state);
        sui::event::emit(MigrateComplete { package });
    }

    #[test_only]
    public fun set_up_migrate(wormhole_state: &mut State) {
        state::reverse_migrate__v__dummy(wormhole_state);
    }
}
