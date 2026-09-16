require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      describe ArchetypePicks do

        def config(use_alignment = false)
          ConfigView.fixture(
            'pf2e' => { 'use_alignment' => use_alignment },
            'pf2e_archetype' => {
              'Druid Archetype' => {
                'key_abil' => [ 'WIS', 'CHA' ],
                'initial_dedication' => { 'combat_stats' => { 'class_dc' => 'trained' } }
              },
              'Champion Archetype' => { 'allowed_sanctifications' => [ 'Holy', 'Unholy' ] },
              'Cleric Archetype' => { 'use_deity' => true }
            },
            'pf2e_archetype_specialty' => {
              'Druid Archetype' => {
                'Animal' => {
                  'initial_dedication' => { 'skills' => [ 'Athletics' ] },
                  'choose' => { 'choice_name' => 'Animal Order', 'options' => { 'Bear' => {}, 'Wolf' => {} } }
                },
                'Leaf' => { 'initial_dedication' => { 'skills' => [ 'Diplomacy' ] } }
              },
              'Bard Archetype' => {
                'Maestro' => { 'choose' => { 'choice_name' => 'Muse', 'options' => { 'Anthem' => {}, 'Lingua' => {} } } }
              },
              'Champion Archetype' => {
                'Beacon' => { 'allowed_alignments' => [ 'WL' ], 'allowed_sanctifications' => [ 'Holy' ] },
                'Justiciar' => { 'allowed_alignments' => [ 'OL' ] }
              }
            },
            'pf2e_deities' => {
              'Aleria' => { 'allowed_alignments' => [ 'WL' ], 'allowed_sanctifications' => [ 'Holy' ], 'divine_skill' => 'Diplomacy' },
              'Maugrim' => { 'allowed_alignments' => [ 'OT' ], 'allowed_sanctifications' => [ 'Unholy' ] }
            }
          )
        end

        def state(to_assign: {}, archetypes: {}, advancement: {}, faith: {}, charclass: 'Fighter', use_alignment: false)
          CharState.build(
            {
              'to_assign' => { 'archetype' => 'Druid Archetype' }.merge(to_assign),
              'archetypes' => archetypes,
              'advancement' => advancement,
              'faith' => faith,
              'base_info' => { 'charclass' => charclass }
            },
            :config => config(use_alignment)
          )
        end

        describe :set do
          it "should refuse a kind of assignment it does not know about" do
            result = ArchetypePicks.set(state, 'hair colour', 'blue')

            expect(result.code).to eq :bad_option
            expect(result.args['options']).to include 'specialty'
          end

          # Every one of these picks belongs to the archetype the Dedication feat staged, so
          # without one there is nothing to answer for.
          it "should refuse when the draft holds no archetype" do
            bare = CharState.build({ 'to_assign' => {} }, :config => config)

            expect(ArchetypePicks.set(bare, 'specialty', 'Animal').code).to eq :no_archetype
          end
        end

        describe "a specialty" do
          def waiting(extra = {})
            state(:to_assign => { 'archetype_specialty' => 'open' }.merge(extra),
              :archetypes => { 'archetype1' => 'Druid Archetype' })
          end

          it "should record the specialty in the draft" do
            result = ArchetypePicks.set(waiting, 'specialty', 'leaf')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['archetype_specialty']).to eq 'Leaf'
          end

          it "should record it in the slot beside its own archetype" do
            result = ArchetypePicks.set(
              state(:to_assign => { 'archetype_specialty' => 'open' },
                :archetypes => { 'archetype1' => 'Bard Archetype', 'archetype2' => 'Druid Archetype' }),
              'specialty', 'Leaf')

            expect(result.state['archetypes']['archetype_specialty2']).to eq 'Leaf'
            expect(result.state['archetypes']['archetype_specialty1']).to be_nil
          end

          it "should refuse a specialty the archetype does not have" do
            result = ArchetypePicks.set(waiting, 'specialty', 'Storm')

            expect(result.code).to eq :bad_specialty
            expect(result.args['options']).to eq 'Animal, Leaf'
          end

          it "should say there is nothing to do when no specialty is open" do
            expect(ArchetypePicks.set(state, 'specialty', 'Leaf').code).to eq :nothing_to_assign
          end

          # A specialty that asks a question of its own - which animal, which dragon - opens it
          # keyed by archetype, so four archetypes can each have one outstanding.
          it "should open the question the specialty itself asks" do
            result = ArchetypePicks.set(waiting, 'specialty', 'Animal')

            expect(result.state['to_assign']['archetype specialty choice']['Druid Archetype'])
              .to eq('specialty' => 'Animal', 'choice' => 'open')
            expect(result.state['archetypes']['archetype_specialty_choice1']).to eq ""
          end

          it "should say what there is to choose from" do
            result = ArchetypePicks.set(waiting, 'specialty', 'Animal')

            expect(result.messages.first['type']).to eq 'ooc'
            expect(result.messages.first['args']['choice']).to eq 'Animal Order'
            expect(result.messages.first['args']['options']).to eq 'Bear, Wolf'
          end

          it "should not open a question for a specialty that asks none" do
            expect(ArchetypePicks.set(waiting, 'specialty', 'Leaf').state['to_assign']['archetype specialty choice']).to be_nil
          end

          # The choice slot is keyed by the archetype's index, so an archetype the sheet has no
          # slot for has nowhere to record an answer.
          it "should not open a question for an archetype holding no slot" do
            result = ArchetypePicks.set(state(:to_assign => { 'archetype_specialty' => 'open' }), 'specialty', 'Animal')

            expect(result.state['to_assign']['archetype specialty choice']).to be_nil
          end

          it "should refuse a Champion cause that contradicts the sanctification already staged" do
            champion = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_specialty' => 'open', 'archetype_sanctification' => 'Unholy' },
              :charclass => 'Fighter')

            result = ArchetypePicks.set(champion, 'specialty', 'Beacon')

            expect(result.code).to eq :champion_specialty_sanctification_mismatch
            expect(result.args['sanctification']).to eq 'Unholy'
          end

          # Nothing settled yet means nothing to contradict: the sanctification pick makes the
          # same comparison the other way round.
          it "should allow a Champion cause when no sanctification is settled yet" do
            champion = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_specialty' => 'open', 'archetype_sanctification' => 'open' })

            expect(ArchetypePicks.set(champion, 'specialty', 'Beacon').ok?).to be true
          end

          it "should refuse a Champion cause the character's alignment does not allow" do
            champion = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_specialty' => 'open' },
              :faith => { 'alignment' => 'OT' },
              :use_alignment => true)

            expect(ArchetypePicks.set(champion, 'specialty', 'Beacon').code).to eq :champion_specialty_alignment_mismatch
          end

          it "should refuse a Champion cause before an alignment has been set" do
            champion = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_specialty' => 'open' },
              :use_alignment => true)

            expect(ArchetypePicks.set(champion, 'specialty', 'Beacon').code).to eq :alignment_missing
          end
        end

        describe "a specialty's own choice" do
          def waiting(choice = 'open', archetype = 'Druid Archetype')
            state(
              :to_assign => {
                'archetype_specialty' => 'Animal',
                'archetype specialty choice' => { archetype => { 'specialty' => 'Animal', 'choice' => choice } }
              },
              :archetypes => { 'archetype1' => 'Druid Archetype' })
          end

          it "should record the choice against its archetype" do
            result = ArchetypePicks.set(waiting, 'specialtychoice', 'wolf')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['archetype specialty choice']['Druid Archetype']['choice']).to eq 'Wolf'
          end

          it "should leave the specialty it belongs to alone" do
            result = ArchetypePicks.set(waiting, 'specialtychoice', 'Wolf')

            expect(result.state['to_assign']['archetype specialty choice']['Druid Archetype']['specialty']).to eq 'Animal'
          end

          it "should record it in the slot beside its archetype" do
            expect(ArchetypePicks.set(waiting, 'specialtychoice', 'Wolf').state['archetypes']['archetype_specialty_choice1']).to eq 'Wolf'
          end

          it "should refuse an option the specialty does not offer" do
            result = ArchetypePicks.set(waiting, 'specialtychoice', 'Badger')

            expect(result.code).to eq :bad_specialty_choice
            expect(result.args['options']).to eq 'Bear, Wolf'
          end

          it "should say there is nothing to do once it has been chosen" do
            expect(ArchetypePicks.set(waiting('Wolf'), 'specialtychoice', 'Bear').code).to eq :nothing_to_assign
          end

          it "should say there is nothing to do when no choice is staged at all" do
            expect(ArchetypePicks.set(state, 'specialtychoice', 'Wolf').code).to eq :nothing_to_assign
          end

          # A player with one outstanding choice should not have to say which archetype it
          # belongs to, so the pick falls back to whichever archetype is waiting - and reads that
          # archetype's config rather than the one being advanced.
          it "should find a choice waiting under another archetype" do
            elsewhere = state(
              :to_assign => {
                'archetype specialty choice' => { 'Bard Archetype' => { 'specialty' => 'Maestro', 'choice' => 'open' } }
              },
              :archetypes => { 'archetype1' => 'Bard Archetype', 'archetype2' => 'Druid Archetype' })

            result = ArchetypePicks.set(elsewhere, 'specialtychoice', 'lingua')

            expect(result.state['to_assign']['archetype specialty choice']['Bard Archetype']['choice']).to eq 'Lingua'
            expect(result.state['archetypes']['archetype_specialty_choice1']).to eq 'Lingua'
          end
        end

        describe "a key ability" do
          def waiting(advancement = {})
            state(:to_assign => { 'archetype key ability' => [ 'WIS', 'CHA' ] }, :advancement => advancement)
          end

          it "should record the ability under the archetype's own class DC" do
            result = ArchetypePicks.set(waiting, 'key ability', 'wis')

            expect(result.ok?).to be true
            expect(result.state['advancement']['combat_stats']['archetype_class_dcs']['Druid Archetype']['key_abil']).to eq 'WIS'
          end

          it "should spend the slot it was offered in" do
            expect(ArchetypePicks.set(waiting, 'key ability', 'WIS').state['to_assign']['archetype key ability']).to eq 'WIS'
          end

          # The proficiency is normally written when the Dedication is taken; a draft that
          # arrived without it would otherwise hold a class DC with no proficiency behind it.
          it "should fill in the proficiency the archetype grants when the draft lacks it" do
            result = ArchetypePicks.set(waiting, 'key ability', 'WIS')

            expect(result.state['advancement']['combat_stats']['archetype_class_dcs']['Druid Archetype']['prof']).to eq 'trained'
          end

          it "should leave a proficiency the draft already holds alone" do
            held = { 'combat_stats' => { 'archetype_class_dcs' => { 'Druid Archetype' => { 'prof' => 'expert' } } } }

            result = ArchetypePicks.set(waiting(held), 'key ability', 'WIS')

            expect(result.state['advancement']['combat_stats']['archetype_class_dcs']['Druid Archetype']['prof']).to eq 'expert'
          end

          it "should refuse an ability the archetype did not offer" do
            result = ArchetypePicks.set(waiting, 'key ability', 'STR')

            expect(result.code).to eq :bad_key_ability
            expect(result.args['options']).to eq 'WIS, CHA'
          end

          it "should say there is nothing to do when the archetype offered no choice" do
            expect(ArchetypePicks.set(state, 'key ability', 'WIS').code).to eq :nothing_to_assign
          end
        end

        describe "a sanctification" do
          it "should refuse for an archetype that has none" do
            waiting = state(:to_assign => { 'archetype_sanctification' => 'open' })

            expect(ArchetypePicks.set(waiting, 'sanctification', 'Holy').code).to eq :nothing_to_assign
          end

          # A Cleric's sanctification comes from their deity, and an archetype cannot move it.
          it "should refuse to move a Cleric's sanctification" do
            waiting = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_sanctification' => 'open' },
              :charclass => 'Cleric')

            result = ArchetypePicks.set(waiting, 'sanctification', 'Holy')

            expect(result.code).to eq :sanctification_locked
            expect(result.args['charclass']).to eq 'Cleric'
          end

          it "should record the sanctification in both halves of the draft" do
            waiting = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_sanctification' => 'open' })

            result = ArchetypePicks.set(waiting, 'sanctification', 'unholy')

            expect(result.state['to_assign']['archetype_sanctification']).to eq 'Unholy'
            expect(result.state['advancement']['archetype_sanctification']).to eq 'Unholy'
          end

          # A Champion taking the Cleric Archetype may only be Holy, whatever their deity says.
          it "should hold a Champion taking the Cleric Archetype to Holy" do
            waiting = state(
              :to_assign => { 'archetype' => 'Cleric Archetype', 'archetype_sanctification' => 'open' },
              :charclass => 'Champion')

            expect(ArchetypePicks.set(waiting, 'sanctification', 'Holy').ok?).to be true
            expect(ArchetypePicks.set(waiting, 'sanctification', 'Unholy').code).to eq :bad_sanctification
          end

          it "should ask for the deity first when the answer depends on one" do
            waiting = state(
              :to_assign => { 'archetype' => 'Cleric Archetype', 'archetype_sanctification' => 'open', 'archetype deity' => 'open' })

            expect(ArchetypePicks.set(waiting, 'sanctification', 'Holy').code).to eq :sanctification_needs_deity
          end

          it "should read the sanctifications the chosen deity allows" do
            waiting = state(
              :to_assign => { 'archetype' => 'Cleric Archetype', 'archetype_sanctification' => 'open', 'archetype deity' => 'Maugrim' })

            expect(ArchetypePicks.set(waiting, 'sanctification', 'Unholy').ok?).to be true
            expect(ArchetypePicks.set(waiting, 'sanctification', 'Holy').code).to eq :bad_sanctification
          end

          # A Champion Archetype cause may allow fewer sanctifications than the archetype does,
          # and once the cause is chosen it governs.
          it "should narrow the options to what the chosen cause allows" do
            waiting = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_sanctification' => 'open', 'archetype_specialty' => 'Beacon' })

            result = ArchetypePicks.set(waiting, 'sanctification', 'Unholy')

            expect(result.code).to eq :bad_sanctification
            expect(result.args['options']).to eq 'Holy'
          end

          it "should not narrow for a cause that has no requirement of its own" do
            waiting = state(
              :to_assign => { 'archetype' => 'Champion Archetype', 'archetype_sanctification' => 'open', 'archetype_specialty' => 'Justiciar' })

            expect(ArchetypePicks.set(waiting, 'sanctification', 'Unholy').ok?).to be true
          end
        end

        describe "a deity" do
          def waiting(extra = {})
            state(:to_assign => { 'archetype deity' => 'open' }.merge(extra))
          end

          it "should record the deity in both halves of the draft" do
            result = ArchetypePicks.set(waiting, 'deity', 'aleria')

            expect(result.ok?).to be true
            expect(result.state['to_assign']['archetype deity']).to eq 'Aleria'
            expect(result.state['advancement']['archetype_deity']).to eq 'Aleria'
          end

          it "should say there is nothing to do when the archetype needs no deity" do
            expect(ArchetypePicks.set(state, 'deity', 'Aleria').code).to eq :nothing_to_assign
          end

          it "should refuse a deity the game does not have" do
            result = ArchetypePicks.set(waiting, 'deity', 'Nobody')

            expect(result.code).to eq :bad_deity
            expect(result.args['options']).to eq 'Aleria, Maugrim'
          end

          # The Champion Archetype carries the Champion class's own restriction with it, from the
          # list chargen rules by.
          it "should refuse a deity no champion may worship" do
            champion = waiting('archetype' => 'Champion Archetype')

            result = ArchetypePicks.set(champion, 'deity', 'Maugrim')

            expect(result.code).to eq :champion_deity_mismatch
          end

          it "should allow that deity to anyone else" do
            expect(ArchetypePicks.set(waiting, 'deity', 'Maugrim').ok?).to be true
          end

          it "should refuse a deity the character's alignment does not allow" do
            mismatched = state(:to_assign => { 'archetype deity' => 'open' },
              :faith => { 'alignment' => 'OT' }, :use_alignment => true)

            expect(ArchetypePicks.set(mismatched, 'deity', 'Aleria').code).to eq :deity_alignment_mismatch
          end
        end
      end

      # The other half: what a settled pick hands over. Skills, spellcasting and features are held
      # on live objects rather than in the draft, so this needs a character. It goes through the same
      # Onboarding rows that apply an archetype's own dedication block, so a specialty's block is
      # read with the same vocabulary.
      describe ArchetypePicks, :dbtest => true do

        before(:each) do
          bootstrapper = AresMUSH::Bootstrapper.new
          bootstrapper.config_reader.load_game_config
          bootstrapper.db.load_config

          @char = Character.create(:name => "Arch#{rand(1000000)}")
          @char.update(:pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' })
        end

        after(:each) do
          Pf2e::Audit.delete_all!(@char) if @char
          @char.delete if @char
        end

        def pick(archetype, type, value, to_assign: {}, advancement: {})
          @char.update(:pf2_archetypeinfo => { 'archetype1' => archetype })
          @char.update(:pf2_to_assign => { 'archetype' => archetype }.merge(to_assign))
          @char.update(:pf2_advancement => advancement)

          outcome = ArchetypePicks.set(Pf2e::CharState.of(@char), type, value)

          raise "pick refused: #{outcome.key}" if outcome.err?

          messages = ArchetypePicks.deliver(@char, outcome.state, type)

          { :to_assign => outcome.state['to_assign'], :advancement => outcome.state['advancement'], :messages => messages }
        end

        it "should train the skills a specialty grants" do
          out = pick('Druid Archetype', 'specialty', 'Animal', :to_assign => { 'archetype_specialty' => 'open' })

          expect(Array(out[:to_assign]['raise skill'])).to include 'Athletics'
        end

        # The Druid Archetype's Animal order grants the Animal Companion feat through its `feat`
        # key, the same key an archetype's own block uses.
        it "should grant the feats a specialty hands over" do
          out = pick('Druid Archetype', 'specialty', 'Animal', :to_assign => { 'archetype_specialty' => 'open' })

          expect(Array(out[:advancement]['feats']['general'])).to include 'Animal Companion'
          expect(Array(out[:to_assign]['feats']['general'])).to include 'Animal Companion'
        end

        it "should stage the spellcasting a specialty brings under the archetype's own key" do
          out = pick('Druid Archetype', 'specialty', 'Animal', :to_assign => { 'archetype_specialty' => 'open' })

          expect(out[:advancement]['magic_stats']['Druid Archetype']['focus_pool']).to eq 1
        end

        # Merged rather than replaced: the dedication's own magic stats are already under this
        # key by the time a specialty is chosen, and replacing them would lose the caster.
        it "should merge a specialty's spellcasting into what the dedication already staged" do
          held = { 'magic_stats' => { 'Sorcerer Archetype' => { 'spell_abil' => 'CHA' } } }

          out = pick('Sorcerer Archetype', 'specialty', 'Aberrant',
            :to_assign => { 'archetype_specialty' => 'open' }, :advancement => held)

          staged = out[:advancement]['magic_stats']['Sorcerer Archetype']

          expect(staged['spell_abil']).to eq 'CHA'
          expect(staged['tradition']).to eq('occult' => 'trained')
        end

        it "should name the specialty when it says which skills it trained" do
          out = pick('Druid Archetype', 'specialty', 'Leaf', :to_assign => { 'archetype_specialty' => 'open' })
          key, args = out[:messages].first

          expect(key).to eq 'pf2e.adv_archetype_specialty_skill_training'
          expect(args[:archetypespecialty]).to eq 'Leaf'
        end

        it "should train the skill a chosen deity grants" do
          deity = Global.read_config('pf2e_deities').keys.find { |d| !Global.read_config('pf2e_deities', d, 'divine_skill').blank? }
          skill = Global.read_config('pf2e_deities', deity, 'divine_skill')

          # The game uses alignments, and a deity will not take a follower whose alignment it
          # does not allow, so the character needs one this deity accepts.
          @char.update(:pf2_faith => { 'alignment' => Array(Global.read_config('pf2e_deities', deity, 'allowed_alignments')).first })

          out = pick('Cleric Archetype', 'deity', deity, :to_assign => { 'archetype deity' => 'open' })

          expect(Array(out[:to_assign]['raise skill'])).to include skill
        end
      end
    end
  end
end
