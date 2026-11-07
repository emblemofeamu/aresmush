require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Ea's 20 dragons replace Pathfinder's, wherever the game offers a dragon.
    describe "Ea's dragons", :dbtest => true do

      # Tradition and damage for each dragon, the same wherever the game offers one.
      DRAGONS = {
        'Avarice' => %w{occult poison}, 'Bestial' => %w{primal poison}, 'Brine' => %w{primal bludgeoning},
        'Cloud' => %w{primal electricity}, 'Crystal' => %w{primal piercing}, 'Delight' => %w{divine spirit},
        'Diabolic' => %w{divine fire}, 'Empyreal' => %w{divine spirit}, 'Executor' => %w{divine sonic},
        'Forest' => %w{primal piercing}, 'Fortune' => %w{arcane force}, 'Madness' => %w{occult mental},
        'Magma' => %w{primal fire}, 'Mocking' => %w{occult bludgeoning}, 'Ossuary' => %w{divine void},
        'Rune' => %w{arcane fire}, 'Terra' => %w{primal bludgeoning}, 'Time' => %w{arcane force},
        'Umbral' => %w{occult void}, 'Whisper' => %w{occult mental}
      }.freeze

      # A draconic sorcerer's 2nd-, 5th- and 8th-rank gifts, for the dragons added after the first fifteen.
      GIFTS = {
        'Delight' => [ 'Laughing Fit', 'Breath of Life', 'Moment of Renewal' ],
        'Executor' => [ 'Revealing Light', 'Divine Immolation', 'Divine Inspiration' ],
        'Mocking' => [ 'Laughing Fit', 'Cloak of Colors', 'Uncontrollable Dance' ],
        'Rune' => [ 'Embed Message', 'Imaginary Lockbox', 'Quandary' ],
        'Time' => [ "Loose Time's Arrow", 'Banishment', 'Quandary' ],
        'Whisper' => [ 'Humanoid Form', 'Scouting Eye', 'Dream Council' ]
      }.freeze

      SKILLS = { 'arcane' => 'Arcana', 'divine' => 'Religion', 'occult' => 'Occultism', 'primal' => 'Nature' }.freeze

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

      it "should offer a draconic sorcerer and either archetype the same dragons" do
        sorcerer = Global.read_config('pf2e_specialty', 'Sorcerer', 'Draconic')['choose']['options'].keys
        barbarian = Global.read_config('pf2e_archetype_specialty', 'Barbarian Archetype', 'Dragon')['choose']['options'].keys
        dedication = Global.read_config('pf2e_archetype_specialty', 'Sorcerer Archetype', 'Draconic')['choose']['options'].keys

        [ sorcerer, barbarian, dedication ].each { |one| expect(one).to match_array DRAGONS.keys }
      end

      it "should give each draconic sorcerer their dragon's tradition and skill" do
        DRAGONS.each do |name, (tradition, _)|
          exemplar = Global.read_config('pf2e_subclass', 'Dragon Exemplar', name)
          dedication = Global.read_config('pf2e_archetype_specialty', 'Sorcerer Archetype', 'Draconic')['choose']['options'][name]['initial_dedication']

          expect(exemplar['chargen']['magic_stats']['tradition']).to eq(tradition => 'trained')
          expect(exemplar['advance'][19]['magic_stats']['tradition']).to eq(tradition => 'legendary')
          expect(exemplar['chargen']['skills']).to eq [ 'Intimidation', SKILLS[tradition] ]
          expect(dedication['magic_stats']['tradition']).to eq(tradition => 'trained')
          expect(dedication['skills']).to eq [ 'Intimidation', SKILLS[tradition] ]
        end
      end

      it "should give a draconic sorcerer their dragon's gifts, each a spell in the catalogue at its rank" do
        expect(Global.read_config('pf2e_subclass', 'get_dragon_spell').keys).to match_array DRAGONS.keys

        GIFTS.each do |name, spells|
          gifts = Global.read_config('pf2e_subclass', 'get_dragon_spell', name)

          expect(gifts).to eq({ 2 => spells[0], 5 => spells[1], 8 => spells[2] })
        end

        Global.read_config('pf2e_subclass', 'get_dragon_spell').each_value do |gifts|
          gifts.each do |rank, spell|
            expect(Global.read_config('pf2e_spells', spell)&.dig('base_level').to_i).to be_between(1, rank)
          end
        end
      end

      it "should make Dragonplate and the Dragonslayer's Shield in each dragon" do
        armor = Global.read_config('pf2e_armor').keys.grep(/\ADragonplate \(/)
        shields = Global.read_config('pf2e_shields').keys.grep(/\ADragonslayer's Shield \(/)

        expect(armor).to match_array DRAGONS.keys.map { |name| "Dragonplate (#{name})" }
        expect(shields).to match_array DRAGONS.keys.map { |name| "Dragonslayer's Shield (#{name})" }
      end

      it "should leave out of the breath's traits only dragons dealing physical damage" do
        breath = form_rules.find { |row| row['key'] == 'ItemAlteration' && row['predicate'] }

        expect(breath['predicate'].first['nor']).to contain_exactly 'dragon-form:brine', 'dragon-form:terra', 'dragon-form:crystal',
                                                                    'dragon-form:forest', 'dragon-form:mocking'
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
          expect(Bestiary.index.keys.grep(/\A(?:Wish|Mirage|Sea) (?:Dragon|Archdragon)/)).to eq []
        end

        it "should list the dragons added to the setting" do
          %w{Delight Executor Mocking Rune Time Whisper}.each do |name|
            expect(Bestiary.index.keys.grep(/\A#{name} (?:Dragon|Archdragon)/)).to_not be_empty
          end
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
