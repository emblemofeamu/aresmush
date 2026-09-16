require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a class table's `combat_stats` block may say, and what happens to a key nobody handles.
    #
    # An unrecognised key is logged rather than dropped: a proficiency a class does not receive
    # leaves no trace on the sheet to notice.
    describe :update_combat_stats do

      def combat_for(char)
        Pf2eCombat.create(:character => char)
      end

      describe "an unknown key", :dbtest => true do
        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Stats#{rand(1000000)}")
          @combat = combat_for(@char)
          # `get_create_combat_obj` follows the character's reference, so without this it would
          # make a second combat object and write to that one instead.
          @char.update(:combat => @combat)
        end

        after(:each) do
          @combat.delete if @combat
          @char.delete if @char
        end

        it "should say so rather than dropping it" do
          expect(Global.logger).to receive(:error).with(/armor_light/)

          Pf2eCombat.update_combat_stats(@char, 'armor_light' => 'expert')
        end

        # The Rogue's table sets sneak_attack at chargen, 5, 11 and 17, and `roll sneak attack`
        # reads it off the combat object.
        it "should record sneak attack dice" do
          Pf2eCombat.update_combat_stats(@char, 'sneak_attack' => '2d6')

          expect(Pf2eCombat[@combat.id].sneak_attack).to eq '2d6'
        end

        it "should let a roll string use them" do
          Pf2eCombat.update_combat_stats(@char, 'sneak_attack' => '2d6')

          rolled = Pf2e.get_keyword_value(Character[@char.id], 'sneak attack')

          expect(rolled).to be_a Array
          expect(rolled.size).to eq 2
          expect(rolled).to all(be_between(1, 6))
        end

        it "should give nothing for a character with no sneak attack" do
          expect(Pf2e.get_keyword_value(Character[@char.id], 'sneak attack')).to eq 0
        end
      end

      # Every `combat_stats` key in every class's chargen and advance blocks has to be one the
      # writer writes, or the class never receives it. Proficiencies nest under `armor_prof` and
      # `weapon_prof`; a bare `light` or `martial` is not a key.
      describe "the shipped class tables" do
        def blocks_for(charclass)
          config = Global.read_config('pf2e_class', charclass) || {}
          advance = (config['advance'] || {}).each_with_object({}) { |(lv, b), out| out[lv.to_s] = b }

          { 'chargen' => config['chargen'] }.merge(advance)
        end

        it "should only use combat stats the writer knows how to write" do
          unknown = []

          (Global.read_config('pf2e_class') || {}).each_key do |charclass|
            blocks_for(charclass).each_pair do |where, block|
              next unless block.is_a?(Hash)

              stats = block['combat_stats']
              next unless stats.is_a?(Hash)

              (stats.keys.map(&:to_s) - Pf2eCombat::STAT_WRITERS.keys - [ 'archetype_class_dcs' ]).each do |key|
                unknown << "#{charclass} at #{where}: combat_stats.#{key}"
              end
            end
          end

          expect(unknown).to eq []
        end
      end
    end
  end
end
