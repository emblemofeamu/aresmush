require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # What the entry shape can hold.
    #
    # The requirement is that the model support anything PF2e does. The parallel hashes could
    # not: every one of them is keyed by a class name, so a source that is not a class - a staff,
    # a wand, a ritual, an ancestry - had nowhere to go, and two sources that agreed on the key
    # collided. These are the cases that were impossible, exercised through the ordinary API so
    # that the model's contract is tested rather than asserted.
    describe "what a spellcasting entry can hold", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Shape#{rand(1000000)}")
        @magic = PF2Magic.get_create_magic_obj(@char)
      end

      after(:each) do
        @char.delete if @char
      end

      def entries
        Entries.for_magic(PF2Magic[@magic.id])
      end

      def find(name)
        entries.find { |e| e['name'] == name }
      end

      # A staff holds spells and spends charges rather than slots, and casts at the wielder's own
      # statistics - none of which a class-keyed hash has a place for.
      it "should hold an item caster with charges" do
        Entries.store!(@char,
          'name' => 'Staff of Fire', 'source_type' => 'item', 'category' => 'item',
          'tradition' => 'arcane', 'ability' => 'Intelligence', 'proficiency' => 'expert',
          'known' => { '1' => [ 'Ignition' ], '3' => [ 'Fireball' ] },
          'uses' => { 'charges' => 3, 'max' => 3 })

        staff = find('Staff of Fire')

        expect(staff['category']).to eq 'item'
        expect(staff['known']['3']).to eq [ 'Fireball' ]
        expect(staff['uses']).to eq('charges' => 3, 'max' => 3)
      end

      # A wand is one spell, once a day.
      it "should hold a wand as its own entry" do
        Entries.store!(@char,
          'name' => 'Wand of Heal', 'source_type' => 'item', 'category' => 'item',
          'tradition' => 'divine', 'known' => { '1' => [ 'Heal' ] },
          'uses' => { 'per_day' => 1 })

        expect(find('Wand of Heal')['uses']).to eq('per_day' => 1)
      end

      # Two staves at once: two entries sharing a category with different traditions, which a hash
      # keyed by class has no room for.
      it "should hold two item casters at once" do
        Entries.store!(@char, 'name' => 'Staff of Fire', 'category' => 'item', 'source_type' => 'item', 'tradition' => 'arcane')
        Entries.store!(@char, 'name' => 'Staff of Healing', 'category' => 'item', 'source_type' => 'item', 'tradition' => 'divine')

        items = entries.select { |e| e['category'] == 'item' }

        expect(items.size).to eq 2
        expect(items.map { |e| e['tradition'] }.sort).to eq [ 'arcane', 'divine' ]
      end

      # Rituals have no slots and are cast with skill checks, so an entry with known spells and
      # no slots is the whole of it.
      it "should hold rituals with no slots" do
        Entries.store!(@char,
          'name' => 'Rituals', 'source_type' => 'ritual', 'category' => 'ritual',
          'known' => { '4' => [ 'Planar Binding' ] })

        rituals = find('Rituals')

        expect(rituals['category']).to eq 'ritual'
        expect(rituals['slots']).to eq({})
        expect(rituals['known']['4']).to eq [ 'Planar Binding' ]
      end

      # Two prepared casters at once - a class and an archetype - each with its own tradition,
      # ability, proficiency and slots. This is what makes an archetype cast at its own DC.
      it "should hold two casters with different statistics" do
        Entries.store!(@char,
          'name' => 'Wizard', 'source_type' => 'class', 'category' => 'prepared',
          'tradition' => 'arcane', 'ability' => 'Intelligence', 'proficiency' => 'master',
          'slots' => { '1' => 3 })
        Entries.store!(@char,
          'name' => 'Cleric Archetype', 'source_type' => 'archetype', 'category' => 'prepared',
          'tradition' => 'divine', 'ability' => 'Wisdom', 'proficiency' => 'trained',
          'slots' => { '1' => 1 })

        expect(find('Wizard')['proficiency']).to eq 'master'
        expect(find('Cleric Archetype')['proficiency']).to eq 'trained'
        expect(find('Cleric Archetype')['tradition']).to eq 'divine'
      end

      # A prepared caster's slots and what is prepared into them are different things, and belong on
      # one entry.
      it "should keep slots and what is prepared into them on one entry" do
        Entries.store!(@char,
          'name' => 'Wizard', 'source_type' => 'class', 'category' => 'prepared',
          'slots' => { '1' => 3, '2' => 2 },
          'known' => { '1' => [ 'Magic Missile', 'Shield' ] },
          'prepared' => { '1' => [ 'Magic Missile', 'Magic Missile', 'Shield' ] })

        wizard = find('Wizard')

        expect(wizard['slots']['1']).to eq 3
        expect(wizard['prepared']['1'].count('Magic Missile')).to eq 2
      end

      it "should keep a spontaneous caster's signature spells on its own entry" do
        Entries.store!(@char,
          'name' => 'Sorcerer', 'source_type' => 'class', 'category' => 'spontaneous',
          'known' => { '3' => [ 'Fireball', 'Haste' ] },
          'signature' => { '3' => [ 'Fireball' ] })

        expect(find('Sorcerer')['signature']).to eq('3' => [ 'Fireball' ])
      end

      # A bloodline's granted spells, a wizard's curriculum, an order's list - whatever narrows
      # what may go in belongs to the entry that is narrowed.
      it "should hold a restriction belonging to one entry only" do
        Entries.store!(@char,
          'name' => 'Wizard', 'source_type' => 'class', 'category' => 'prepared',
          'restrictions' => { 'Battle Magic' => { '1' => 1 } })
        Entries.store!(@char,
          'name' => 'Sorcerer Archetype', 'source_type' => 'archetype', 'category' => 'spontaneous')

        expect(find('Wizard')['restrictions']).to eq('Battle Magic' => { '1' => 1 })
        expect(find('Sorcerer Archetype')['restrictions']).to eq({})
      end

      describe "identity" do
        it "should update an entry rather than duplicating it" do
          Entries.store!(@char, 'name' => 'Wizard', 'category' => 'prepared', 'slots' => { '1' => 2 })
          Entries.store!(@char, 'name' => 'Wizard', 'category' => 'prepared', 'slots' => { '1' => 3 })

          wizards = entries.select { |e| e['name'] == 'Wizard' }

          expect(wizards.size).to eq 1
          expect(wizards.first['slots']).to eq('1' => 3)
        end

        # Name alone is not identity. The same name in two categories is two entries - a Bard's
        # spell repertoire and their composition focus spells, say.
        it "should treat the same name in two categories as two entries" do
          Entries.store!(@char, 'name' => 'Bard', 'category' => 'spontaneous')
          Entries.store!(@char, 'name' => 'Bard', 'category' => 'focus')

          expect(entries.count { |e| e['name'] == 'Bard' }).to eq 2
        end

        # Nor is name and category. Two sources of one focus type differ only by who granted them.
        it "should treat two granting sources as two entries" do
          Entries.store!(@char, 'name' => 'devotion', 'category' => 'focus', 'granted_by' => 'Champion')
          Entries.store!(@char, 'name' => 'devotion', 'category' => 'focus', 'granted_by' => 'Champion Archetype')

          expect(entries.count { |e| e['name'] == 'devotion' }).to eq 2
        end
      end

      # The seam. A category that has rows is served from them; one that has not is still
      # projected from the legacy hashes, and a reader cannot tell which.
      it "should serve a migrated category from rows and project the rest" do
        @magic.update(:tradition => { 'Sorcerer' => [ 'arcane', 'expert' ] },
                      :repertoire => { 'Sorcerer' => { '1' => [ 'Bless' ] } })
        Entries.store!(@char, 'name' => 'devotion', 'category' => 'focus', 'granted_by' => 'Champion',
                       'known' => { 'spell' => [ 'Lay on Hands' ] })

        categories = entries.map { |e| e['category'] }

        expect(categories).to include 'focus'
        expect(categories).to include 'spontaneous'
        expect(find('Sorcerer')['known']).to eq('1' => [ 'Bless' ])
      end
    end
  end
end
