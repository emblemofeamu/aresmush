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

      def counts(char, source = 'Sorcerer')
        known(char, source).transform_values { |spells| Array(spells).size }
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

        at_five = counts(char)

        expect(Pf2e.rollback_to_level(char, 5)).to be_nil
        char = Character[char.id]

        at_four = counts(char)

        expect(char.pf2_level).to eq 4
        expect(at_four).to_not eq at_five
        expect(at_four.values.sum).to be < at_five.values.sum
      end

      it "should give them back on a redo" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Sorcerer', 5)

        at_five = counts(char)

        Pf2e.rollback_to_level(char, 5)
        char = Character[char.id]

        expect(Pf2e.redo_rollback(char)).to be_nil
        char = Character[char.id]

        expect(char.pf2_level).to eq 5
        expect(counts(char)).to eq at_five
      end

      # A prepared enumerated caster keeps a spellbook rather than a repertoire, and the
      # materialiser has to write back to whichever list the casting mode uses.
      it "should ladder a prepared caster's spellbook too" do
        builder = AutoBuilder.new(@char)
        char = builder.build('Wizard', 5)

        expect(builder.summary['level']).to eq 5

        at_five = counts(char, 'Wizard')

        expect(at_five.values.sum).to be > 0

        Pf2e.rollback_to_level(char, 5)
        char = Character[char.id]

        expect(counts(char, 'Wizard').values.sum).to be < at_five.values.sum
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
