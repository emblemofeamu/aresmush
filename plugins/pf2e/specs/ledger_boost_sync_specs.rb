require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Attribute boosts, diffed into grants.
    #
    # A boost is not a thing you hold once: a character can boost Strength at 5, 10, 15 and 20,
    # and the sheet records that as a count. So the diff between what the fold knows and what the
    # character has is a *number* of grants, which is a shape of its own - `list` and `bucketed`
    # both collapse duplicates, and `ranked` would read a second boost as a changed value.
    #
    # Which is what lets a rollback take a boost back: the score is derived from the count rather
    # than written into `base_val` and left there.
    describe "syncing attribute boosts" do

      def plan(held, wanted)
        Ledger.sync_plan({ 'boosts' => held }, { 'boosts' => wanted })
      end

      it "should grant one boost for a new one" do
        outcome = plan({}, 'Strength' => 1)

        expect(outcome['grants']).to eq [ { 'kind' => 'boost_ability', 'payload' => { 'ability' => 'Strength' } } ]
      end

      it "should grant one per boost for several of the same ability" do
        outcome = plan({}, 'Strength' => 3)

        expect(outcome['grants'].size).to eq 3
        expect(outcome['grants'].map { |g| g['payload']['ability'] }).to eq %w(Strength Strength Strength)
      end

      it "should grant only the difference when some are already recorded" do
        outcome = plan({ 'Strength' => 2 }, 'Strength' => 3)

        expect(outcome['grants'].size).to eq 1
        expect(outcome['revocations']).to eq []
      end

      it "should grant nothing when nothing changed" do
        outcome = plan({ 'Strength' => 2, 'Wisdom' => 1 }, 'Strength' => 2, 'Wisdom' => 1)

        expect(outcome['grants']).to eq []
        expect(outcome['revocations']).to eq []
      end

      it "should handle several abilities at once" do
        outcome = plan({}, 'Strength' => 1, 'Dexterity' => 2)

        expect(outcome['grants'].map { |g| g['payload']['ability'] }.tally)
          .to eq('Strength' => 1, 'Dexterity' => 2)
      end

      # Revoking one boost of four must not take the other three with it, so the revocation carries
      # a limit - as a repeatable feat's does.
      it "should revoke one boost at a time when a count falls" do
        outcome = plan({ 'Strength' => 3 }, 'Strength' => 1)

        expect(outcome['grants']).to eq []
        expect(outcome['revocations'].size).to eq 2
        expect(outcome['revocations'].first).to eq(
          'kind' => 'boost_ability',
          'match' => { 'ability' => 'Strength' },
          'limit' => 1
        )
      end

      it "should revoke every boost of an ability the character no longer has" do
        outcome = plan({ 'Wisdom' => 2 }, {})

        expect(outcome['revocations'].size).to eq 2
        expect(outcome['revocations'].map { |r| r['match']['ability'] }).to eq %w(Wisdom Wisdom)
      end
    end
  end
end
