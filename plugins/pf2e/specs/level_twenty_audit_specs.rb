require "plugin_test_loader"
require_relative "support/auto_builder"
require_relative "support/expected_sheet"
require_relative "support/sheet_audit"

module AresMUSH
  module Pf2e

    # Every class from nothing to level 20, with the whole finished sheet checked against what its
    # own tables promised - not just how many feats it holds.
    #
    # The dimensions are in Pf2e::SheetAudit and the expectation is folded out of config by
    # Pf2e::ExpectedSheet. Whether the tables match PF2e is asserted separately in
    # class_table_specs.rb, so a config that drifts from the rules fails there and an engine that
    # drifts from config fails here.
    describe "the level 20 audit", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        SheetAudit.reset_cache!

        @char = Character.create(:name => "Audit#{rand(1000000)}")
      end

      after(:each) do
        @char.delete if @char
      end

      def self.class_names
        (Global.read_config('pf2e_class') || {}).keys.sort
      end

      class_names.each do |charclass|
        it "should finish a #{charclass} with everything its tables promised" do
          builder = AutoBuilder.new(@char)

          # The ability totals at level 1, because nothing on the finished sheet records what
          # they were before the boosts.
          builder.build_level_one(charclass)
          baseline = { 'ability_total' => SheetAudit.ability_total(Character[@char.id]) }

          builder.advance_to(20)

          char = Character[@char.id]

          if char.pf2_level != 20
            fail "#{charclass} stalled at #{char.pf2_level}: #{builder.notes.last(2).join(' | ')}"
          end

          mismatches = SheetAudit.diff(char, charclass, 20, baseline)

          # Report every one, so a climb that is wrong in six ways says so once.
          fail "#{charclass} at 20:\n  " + mismatches.join("\n  ") unless mismatches.empty?
        end
      end
    end
  end
end
