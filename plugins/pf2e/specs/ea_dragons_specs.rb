require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Ea's 15 dragons replace Pathfinder's, wherever the game offers a dragon.
    describe "Ea's dragons", :dbtest => true do

      # Tradition and damage for each dragon, the same wherever the game offers one.
      DRAGONS = {
        'Avarice' => %w{occult poison}, 'Bestial' => %w{primal poison}, 'Brine' => %w{primal bludgeoning},
        'Cloud' => %w{primal electricity}, 'Crystal' => %w{primal piercing}, 'Diabolic' => %w{divine fire},
        'Empyreal' => %w{divine spirit}, 'Forest' => %w{primal piercing}, 'Fortune' => %w{arcane force},
        'Madness' => %w{occult mental}, 'Magma' => %w{primal fire}, 'Mirage' => %w{arcane mental},
        'Ossuary' => %w{divine void}, 'Terra' => %w{primal bludgeoning}, 'Umbral' => %w{occult void}
      }.freeze

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config
        Bestiary.reset!
      end

      after(:each) { Bestiary.reset! }

      def choices_in(rules, flag)
        rules.find { |row| row['key'] == 'ChoiceSet' && row['flag'] == flag }['choices']
      end

      def figures(choices, suffix)
        choices.to_h do |one|
          [ one['label'].delete_suffix(suffix), [ one['value']['tradition'], one['value']['damageType'] ] ]
        end
      end

      let(:form_rules) { ActiveEffects.info('Spell Effect: Dragon Form')['rules'] }

      it "should offer exactly these in Dragon Form, with their figures" do
        expect(figures(choices_in(form_rules, 'dragonForm'), ' Dragon')).to eq DRAGONS
      end

      it "should offer exactly these in Dragon Instinct's rule, with their figures" do
        rules = Global.read_config('pf2e_class_features', 'Dragon Instinct')['rules']

        expect(figures(choices_in(rules, 'dragon'), '')).to eq DRAGONS
      end

      it "should agree with what a character picks from, and what the game records of each" do
        specialty = Global.read_config('pf2e_specialty', 'Barbarian', 'Dragon')['choose']['options'].keys
        types = Global.read_config('pf2e_subclass', 'Dragon Types')

        expect(specialty).to match_array DRAGONS.keys
        expect(types.transform_values { |one| one['element'] }).to eq DRAGONS.transform_values(&:last)
      end

      it "should leave out of the breath's traits only dragons dealing physical damage" do
        breath = form_rules.find { |row| row['key'] == 'ItemAlteration' && row['predicate'] }

        expect(breath['predicate'].first['nor']).to contain_exactly 'dragon-form:brine', 'dragon-form:terra', 'dragon-form:crystal', 'dragon-form:forest'
      end

      describe "a barbarian's Dragon Instinct" do
        before(:each) do
          @char = Character.create(:name => "Instinct#{rand(1000000)}")
          @char.update(:pf2_level => 3, :pf2_feats => {}, :pf2_features => {}, :pf2_traits => [], :pf2_conditions => {},
                       :pf2_base_info => { 'charclass' => 'Barbarian', 'specialize' => 'Dragon', 'specialize_info' => 'Brine' })
        end

        after(:each) { @char.delete }

        it "should read the dragon they picked" do
          instinct = Effects.features(Character[@char.id]).find { |one| one['name'] == 'Dragon Instinct' }

          expect(instinct['item']['flags']['system']['rulesSelections']['dragon']['damageType']).to eq 'bludgeoning'
        end
      end

      describe "the bestiary" do
        it "should call the kept dragons by Ea's names" do
          expect(Bestiary.named('Terra Dragon (Adult)')).to eq 'Terra Dragon (Adult)'
          expect(Bestiary.named('Terra Archdragon (Spellcaster)')).to eq 'Terra Archdragon (Spellcaster)'
          expect(Bestiary.named('Bestial Dragon (Juvenile, BB)')).to_not be_nil
          expect(Bestiary.entry('Terra Dragon (Adult)')['level']).to eq 13
        end

        it "should not know the kept dragons by Pathfinder's names" do
          expect(Bestiary.named('Adamantine Dragon (Adult)')).to be_nil
          expect(Bestiary.find('Sovereign').err?).to be true
        end

        it "should keep the dragons not in the setting out of every list" do
          expect(Bestiary.named('Barrage Dragon (Adult)')).to be_nil
          expect(Bestiary.find('Barrage').err?).to be true
          expect(Bestiary.search('sky')).to_not include(satisfy { |name, _| name.start_with?('Sky Dragon') })
          expect(Bestiary.index.keys.grep(/\A(?:Wish|Time|Sea) (?:Dragon|Archdragon)/)).to eq []
        end

        it "should keep those dragons' data" do
          expect(Bestiary.entry('Barrage Dragon (Adult)')['level']).to eq 12
        end

        it "should leave other dragon-kin visible" do
          %w{Wyvern Tatzlwyrm}.each { |name| expect(Bestiary.named(name)).to eq name }
          expect(Bestiary.named('Zombie Dragon')).to eq 'Zombie Dragon'
          expect(Bestiary.named('Tor Linnorm')).to eq 'Tor Linnorm'
        end
      end
    end
  end
end
