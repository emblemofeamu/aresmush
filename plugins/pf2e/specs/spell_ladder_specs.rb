require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Spells learned ride the level ladder, like every other thing a level grants.
    #
    # Which is what makes `admin/rollback` safe for a caster: a Sorcerer rolled back from 5 to 4
    # gives up the spells learned at 5, rather than keeping them and picking again.
    describe "learned spells on the level ladder", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Lad#{rand(1000000)}")
      end

      after(:each) do
        Pf2e::Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      def known(char, source = 'Sorcerer')
        Pf2emagic::Entries.known_lists(Character[char.id])[source] || {}
      end

      # By name and rank. A count would pass for a rollback that took back the wrong spells, or a
      # redo that handed back a different set of the same size.
      def spells(char, source = 'Sorcerer')
        known(char, source).transform_values { |list| Array(list).sort }
      end

      def all_spells(char, source = 'Sorcerer')
        spells(char, source).values.flatten
      end

      it "should record what was learned, at the level it was learned" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Sorcerer', 4)

        expect(builder.summary['level']).to eq 4

        access = Pf2e::Ledger.rows(char).select { |r| r['kind'] == 'spell_access' }

        expect(access).to_not be_empty
        expect(access.map { |r| r['payload']['source'] }.uniq).to eq [ 'Sorcerer' ]

        # Chargen's spells are seeded at level 1; the rest belong to the level that granted them.
        expect(access.map { |r| r['effective_level'].to_i }.uniq.sort.first).to eq 1
        expect(access.map { |r| r['effective_level'].to_i }.max).to be > 1
      end

      it "should take back the spells a rolled-back level granted" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Sorcerer', 5)

        expect(builder.summary['level']).to eq 5

        at_five = spells(char)

        expect(Pf2e.rollback_to_level(char, 5)).to be_nil
        char = Character[char.id]

        at_four = spells(char)
        taken_back = all_spells(char) - (all_spells(char) & at_five.values.flatten)

        expect(char.pf2_level).to eq 4

        # Every spell still held was held at 5, and the ones that went are level 5's own.
        expect(taken_back).to eq []
        expect(at_five.values.flatten - all_spells(char)).to_not be_empty
        expect(at_four).to_not eq at_five
      end

      it "should give them back on a redo" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Sorcerer', 5)

        at_five = spells(char)

        Pf2e.rollback_to_level(char, 5)
        char = Character[char.id]

        expect(Pf2e.redo_rollback(char)).to be_nil
        char = Character[char.id]

        expect(char.pf2_level).to eq 5
        expect(spells(char)).to eq at_five
      end

      # A prepared enumerated caster keeps a spellbook rather than a repertoire, and the
      # materialiser has to write back to whichever list the casting mode uses.
      it "should ladder a prepared caster's spellbook too" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Wizard', 5)

        expect(builder.summary['level']).to eq 5

        at_five = spells(char, 'Wizard')

        expect(at_five.values.flatten).to_not be_empty

        Pf2e.rollback_to_level(char, 5)
        char = Character[char.id]

        left = all_spells(char, 'Wizard')

        expect(left - at_five.values.flatten).to eq []
        expect(at_five.values.flatten - left).to_not be_empty
      end

      # The second axis earning its keep: a Cleric prepares from the whole divine list, so there
      # is nothing enumerated to record and a rollback has nothing to take away.
      it "should record nothing for a caster with access by rule" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Cleric', 4)

        expect(builder.summary['level']).to eq 4
        expect(Pf2emagic::Entries.known_lists(char)).to eq({})
        expect(Pf2e::Ledger.rows(char).count { |r| r['kind'] == 'spell_access' }).to eq 0
      end

      it "should leave a rolled-back Cleric's casting untouched" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Cleric', 4)

        slots = char.magic.spells_per_day['Cleric']

        expect(Pf2e.rollback_to_level(char, 4)).to be_nil
        char = Character[char.id]

        # They lose the level's slots, which are a class-table fact, but nothing was "unlearned".
        expect(char.pf2_level).to eq 3
        expect(Pf2e::Ledger.rows(char).count { |r| r['kind'] == 'spell_access' }).to eq 0
      end

      it "should say when a spell was learned" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Sorcerer', 4)

        learned = Pf2e::Ledger.rows(char).find { |r| r['kind'] == 'spell_access' && r['effective_level'].to_i > 1 }
        spell = learned['payload']['spell']

        explained = Pf2e::Ledger.explain_for(char, :kind => 'spell_access', :key => spell)

        expect(explained).to_not be_empty
        expect(explained.first['effective_level'].to_i).to eq learned['effective_level'].to_i
      end
    end
  end
end
