require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Deriving spellcasting entries from the eighteen parallel hashes.
    #
    # Pure, so the mapping can be proven before any reader is moved onto it. The point of the
    # entry shape is that "which source" stops being a key convention that each attribute
    # invents for itself - class here, focus type there, spell name for innate - and becomes
    # the identity of a row.
    describe Entries do

      def caster_types
        { 'Sorcerer' => 'spontaneous', 'Wizard' => 'prepared', 'Bard Archetype' => 'spontaneous' }
      end

      def derive(magic)
        Entries.derive(magic, :caster_types => caster_types)
      end

      describe "a casting class" do
        def magic
          {
            'tradition' => { 'Sorcerer' => [ 'arcane', 'expert' ], 'innate' => [ 'innate', 'trained' ] },
            'spell_abil' => { 'Sorcerer' => 'Charisma' },
            'spells_per_day' => { 'Sorcerer' => { 'cantrip' => 5, '1' => 3 } },
            'repertoire' => { 'Sorcerer' => { 'cantrip' => [ 'Ignition' ], '1' => [ 'Bless' ] } },
            'signature_spells' => { 'Sorcerer' => { '1' => [ 'Bless' ] } }
          }
        end

        it "should make one entry per casting class" do
          expect(derive(magic).map { |e| e['name'] }).to eq [ 'Sorcerer' ]
        end

        it "should carry the class's own tradition, ability and proficiency" do
          entry = derive(magic).first

          expect(entry['tradition']).to eq 'arcane'
          expect(entry['proficiency']).to eq 'expert'
          expect(entry['ability']).to eq 'Charisma'
          expect(entry['category']).to eq 'spontaneous'
          expect(entry['source_type']).to eq 'class'
        end

        it "should carry its known spells and slots" do
          entry = derive(magic).first

          expect(entry['known']).to eq('cantrip' => [ 'Ignition' ], '1' => [ 'Bless' ])
          expect(entry['slots']).to eq('cantrip' => 5, '1' => 3)
          expect(entry['signature']).to eq('1' => [ 'Bless' ])
        end

        # The default value of `tradition` carries an 'innate' key, which is not a class. Taking
        # it for one is the kind of mistake the parallel hashes invite.
        it "should not mistake the innate tradition key for a class" do
          expect(derive(magic).map { |e| e['name'] }).to_not include 'innate'
        end

        it "should read a prepared caster's spellbook rather than a repertoire" do
          prepared = {
            'tradition' => { 'Wizard' => [ 'arcane', 'trained' ] },
            'spellbook' => { 'Wizard' => { '1' => [ 'Magic Missile' ] } }
          }

          entry = derive(prepared).first

          expect(entry['category']).to eq 'prepared'
          expect(entry['known']).to eq('1' => [ 'Magic Missile' ])
        end

        it "should carry a curriculum restriction as the entry's own" do
          restricted = {
            'tradition' => { 'Wizard' => [ 'arcane', 'trained' ] },
            'restricted_spellbook' => { 'Wizard' => { 'Battle Magic' => { '1' => 1 } } }
          }

          expect(derive(restricted).first['restrictions']).to eq('Battle Magic' => { '1' => 1 })
        end

        # The reason an archetype is a source in its own right: it has its own tradition and
        # proficiency, and PF2e casts from it at those, not the base class's.
        it "should make an archetype its own entry" do
          both = {
            'tradition' => { 'Sorcerer' => [ 'arcane', 'expert' ], 'Bard Archetype' => [ 'occult', 'trained' ] },
            'repertoire' => { 'Sorcerer' => { '1' => [ 'Bless' ] }, 'Bard Archetype' => { 'cantrip' => [ 'Courageous Anthem' ] } }
          }

          entries = derive(both)

          expect(entries.map { |e| e['name'] }.sort).to eq [ 'Bard Archetype', 'Sorcerer' ]
          expect(entries.find { |e| e['name'] == 'Bard Archetype' }['source_type']).to eq 'archetype'
          expect(entries.find { |e| e['name'] == 'Bard Archetype' }['tradition']).to eq 'occult'
        end
      end

      describe "innate spells" do
        def magic
          {
            'innate_spells' => [
              { 'name' => 'Detect Magic', 'level' => 'cantrip', 'tradition' => 'arcane', 'cast_stat' => 'Charisma' },
              { 'name' => 'Dancing Lights', 'level' => 'cantrip', 'tradition' => 'arcane', 'cast_stat' => 'Charisma' },
              { 'name' => 'Bless', 'level' => '1', 'tradition' => 'divine', 'cast_stat' => 'Wisdom' }
            ]
          }
        end

        it "should group innate spells by the tradition they are cast with" do
          innate = derive(magic).select { |e| e['category'] == 'innate' }

          expect(innate.map { |e| e['tradition'] }.sort).to eq [ 'arcane', 'divine' ]
        end

        it "should carry the ability each is cast off" do
          divine = derive(magic).find { |e| e['category'] == 'innate' && e['tradition'] == 'divine' }

          expect(divine['ability']).to eq 'Wisdom'
          expect(divine['known']).to eq('1' => [ 'Bless' ])
        end

        it "should keep innate spells at the rank they are granted at" do
          arcane = derive(magic).find { |e| e['category'] == 'innate' && e['tradition'] == 'arcane' }

          expect(arcane['known']['cantrip'].sort).to eq [ 'Dancing Lights', 'Detect Magic' ]
        end

        # The collision the list shape exists to prevent. Charm really is granted twice in this
        # game - by Enthralling Allure at rank 4 divine, and by Supernatural Charm at rank 1
        # arcane - and keyed by spell name one of them was simply lost.
        it "should keep two grants of the same spell apart" do
          both = {
            'innate_spells' => [
              { 'name' => 'Charm', 'level' => 4, 'tradition' => 'divine', 'cast_stat' => 'Charisma' },
              { 'name' => 'Charm', 'level' => 1, 'tradition' => 'arcane', 'cast_stat' => 'Charisma' }
            ]
          }

          entries = derive(both).select { |e| e['category'] == 'innate' }

          expect(entries.size).to eq 2
          expect(entries.map { |e| e['tradition'] }.sort).to eq [ 'arcane', 'divine' ]
          expect(entries.find { |e| e['tradition'] == 'divine' }['known']).to eq('4' => [ 'Charm' ])
          expect(entries.find { |e| e['tradition'] == 'arcane' }['known']).to eq('1' => [ 'Charm' ])
        end

        # Six sources grant an unchosen spell. As a single 'open' key, taking two of them lost a
        # pick - and they do not agree on the ability it is cast off.
        it "should keep two unchosen grants apart" do
          pending_two = {
            'innate_spells' => [
              { 'name' => 'open', 'level' => 'cantrip', 'tradition' => 'arcane', 'cast_stat' => 'Intelligence' },
              { 'name' => 'open', 'level' => 'cantrip', 'tradition' => 'arcane', 'cast_stat' => 'Charisma' }
            ]
          }

          entries = derive(pending_two).select { |e| e['category'] == 'innate' }

          expect(entries.size).to eq 2
          expect(entries.map { |e| e['ability'] }.sort).to eq [ 'Charisma', 'Intelligence' ]
        end
      end

      describe "a character with nothing" do
        it "should derive no entries at all" do
          expect(derive({})).to eq []
        end

        it "should derive nothing from the default tradition alone" do
          expect(derive('tradition' => { 'innate' => [ 'innate', 'trained' ] })).to eq []
        end
      end

      describe :signature_ranks do
        def magic
          double(
            :tradition => { 'Sorcerer' => [ 'arcane', 'expert' ] },
            :spell_abil => {}, :spells_per_day => {},
            :repertoire => { 'Sorcerer' => { '3' => [ 'Fireball' ] } },
            :spellbook => {},
            :signature_spells => { 'Sorcerer' => { '3' => [ 'Fireball' ], '5' => [ 'Cone of Cold' ] } },
            :restricted_spellbook => {}, :focus_spells => {}, :focus_cantrips => {}, :innate_spells => [],
            # No character behind it, so nothing is stored and the projection is what answers.
            :character => nil
          )
        end

        before(:each) { allow(Pf2emagic).to receive(:get_caster_type).and_return('spontaneous') }

        it "should give the ranks a spell is a signature at" do
          expect(Entries.signature_ranks(magic, 'Sorcerer', 'Fireball')).to eq [ '3' ]
        end

        it "should give nothing for a spell that is not one" do
          expect(Entries.signature_ranks(magic, 'Sorcerer', 'Haste')).to eq []
        end

        it "should give nothing for a source that does not cast" do
          expect(Entries.signature_ranks(magic, 'Bard', 'Fireball')).to eq []
        end

        # An exact match loses the heightening when a spell is recorded and cast with different
        # capitalisation.
        it "should match the spell however it was capitalised" do
          expect(Entries.signature_ranks(magic, 'Sorcerer', 'fireball')).to eq [ '3' ]
        end

        it "should match the source however it was capitalised" do
          expect(Entries.signature_ranks(magic, 'sorcerer', 'Fireball')).to eq [ '3' ]
        end

        it "should report the sources that have any signature spell" do
          expect(Entries.with_signatures(magic).map { |e| e['name'] }).to eq [ 'Sorcerer' ]
        end
      end

      describe :for_character do
        it "should read the attributes off a magic object" do
          # A plain double is enough: the deriver only reads the attributes.
          magic = double(
            :tradition => { 'Sorcerer' => [ 'arcane', 'expert' ] },
            :spell_abil => { 'Sorcerer' => 'Charisma' },
            :spells_per_day => {}, :repertoire => { 'Sorcerer' => { '1' => [ 'Bless' ] } },
            :spellbook => {}, :signature_spells => {}, :restricted_spellbook => {},
            :focus_spells => {}, :focus_cantrips => {}, :innate_spells => [], :character => nil
          )

          allow(Pf2emagic).to receive(:get_caster_type).with('Sorcerer').and_return('spontaneous')

          entries = Entries.for_magic(magic)

          expect(entries.map { |e| e['name'] }).to eq [ 'Sorcerer' ]
          expect(entries.first['known']).to eq('1' => [ 'Bless' ])
        end
      end
    end
  end
end
