require "plugin_test_loader"

module AresMUSH
  module Pf2e
    describe AdminSet do

      def config
        ConfigView.fixture(
          'pf2e' => { 'allowed_alignments' => [ 'N', 'CN', 'LG' ] },
          'pf2e_skills' => { 'Arcana' => {}, 'Stealth' => {} },
          'pf2e_spells' => { 'Fireball' => {}, 'Fire Shield' => {}, 'Heal' => {} },
          'pf2e_magic' => {
            'prepared_casters' => [ 'Wizard' ],
            'spontaneous_casters' => [ 'Bard' ],
            'focus_type_by_source' => { 'Cleric' => 'divine' }
          },
          'pf2e_deities' => { 'Pharasma' => { 'allowed_alignments' => [ 'N' ] } }
        )
      end

      def state(faith: {}, scores: { 'Strength' => 10 })
        CharState.build(
          { 'name' => 'Tester', 'faith' => faith, 'approved' => true,
            'abilities' => scores.keys, 'ability_scores' => scores },
          :sheet => {
            'features' => { 'charclass_features' => [ 'Arcane Bond' ] },
            'lores' => { 'Sailing Lore' => 'trained' }
          },
          :config => config
        )
      end

      def plan(item, *words)
        AdminSet.plan(state, item, words)
      end

      describe "the targets it knows" do
        it "should refuse a keyword that is not one of them" do
          result = AdminSet.plan(state, 'hair colour', [ 'Blue' ])

          expect(result.err?).to be true
          expect(result.code).to eq :unknown_target
          expect(result.args['options']).to include 'divine font'
        end

        it "should name every target in the help text" do
          expect(AdminSet.targets).to include('skill', 'feature', 'spellbook', 'repertoire',
                                              'focus', 'ability', 'divine font', 'alignment', 'deity')
        end
      end

      describe "a skill" do
        it "should raise a configured skill through the ledger" do
          result = plan('skill', 'Arcana', 'Expert')

          expect(result.ok?).to be true
          expect(result.grants).to eq [ { 'kind' => 'raise_skill',
                                          'payload' => { 'skill' => 'Arcana', 'to' => 'expert' } } ]
        end

        it "should raise a lore the character already holds" do
          result = plan('skill', 'Sailing', 'Lore', 'Master')

          expect(result.grants.first['kind']).to eq 'add_lore'
          expect(result.grants.first['payload']).to eq('lore' => 'Sailing Lore', 'to' => 'master')
        end

        it "should refuse a proficiency that is not a rank" do
          result = plan('skill', 'Arcana', 'Amazing')

          expect(result.code).to eq :bad_prof
        end

        it "should refuse a skill the game does not have" do
          result = plan('skill', 'Basket', 'Weaving', 'Expert')

          expect(result.code).to eq :bad_skill
        end
      end

      describe "a feature" do
        it "should grant one it is told to add" do
          result = plan('feature', 'Add', 'Shield', 'Block')

          expect(result.grants).to eq [ { 'kind' => 'grant_feature',
                                          'payload' => { 'bucket' => 'charclass_features',
                                                         'feature' => 'Shield Block' } } ]
        end

        it "should revoke one it is told to delete" do
          result = plan('feature', 'Delete', 'Arcane', 'Bond')

          expect(result.grants).to be_empty
          expect(result.revocations).to eq [ { 'kind' => 'grant_feature',
                                              'match' => { 'feature' => 'Arcane Bond' } } ]
        end

        it "should refuse to delete one the character has not got" do
          result = plan('feature', 'Delete', 'Arcane', 'Bind')

          expect(result.code).to eq :not_in_list
        end

        it "should refuse an instruction that is neither add nor delete" do
          result = plan('feature', 'Improve', 'Arcane', 'Bond')

          expect(result.code).to eq :bad_instruction
        end
      end

      describe "a spell list" do
        it "should record a spellbook addition as access at that rank" do
          result = plan('spellbook', 'Wizard', 'Add', 'Fireball', '3')

          expect(result.grants).to eq [ { 'kind' => 'spell_access',
                                          'payload' => { 'source' => 'Wizard', 'rank' => '3',
                                                         'spell' => 'Fireball' } } ]
        end

        it "should read a multi-word spell name with the rank last" do
          result = plan('spellbook', 'Wizard', 'Add', 'Fire', 'Shield', '4')

          expect(result.grants.first['payload']).to eq('source' => 'Wizard', 'rank' => '4',
                                                       'spell' => 'Fire Shield')
        end

        it "should file a rank of zero as a cantrip" do
          result = plan('repertoire', 'Bard', 'Add', 'Fireball', '0')

          expect(result.grants.first['payload']['rank']).to eq 'cantrip'
        end

        it "should revoke access on a delete" do
          result = plan('repertoire', 'Bard', 'Delete', 'Fireball', '3')

          expect(result.revocations).to eq [ { 'kind' => 'spell_access',
                                              'match' => { 'source' => 'Bard', 'spell' => 'Fireball' } } ]
        end

        it "should name the list the class actually keeps, whichever keyword was typed" do
          expect(plan('repertoire', 'Wizard', 'Add', 'Fireball', '3').messages.first['args']['element']).to eq 'Spellbook'
          expect(plan('spellbook', 'Bard', 'Add', 'Fireball', '3').messages.first['args']['element']).to eq 'Repertoire'
        end

        it "should send a focus-only class to the focus keyword" do
          result = plan('spellbook', 'Cleric', 'Add', 'Heal', '1')

          expect(result.code).to eq :use_focus_keyword
        end

        it "should refuse a spell name that matches more than one spell" do
          result = plan('spellbook', 'Wizard', 'Add', 'Fire', '3')

          expect(result.code).to eq :not_unique
        end
      end

      describe "an ability score" do
        it "should record the score outright, since no count of boosts reaches 15" do
          result = plan('ability', 'Strength', '15')

          expect(result.grants).to eq [ { 'kind' => 'set_ability_score',
                                          'payload' => { 'ability' => 'Strength', 'to' => 15 } } ]
        end

        it "should refuse a score that is not positive" do
          expect(plan('ability', 'Strength', '0').code).to eq :bad_score
        end

        it "should refuse an attribute the character has not got" do
          expect(plan('ability', 'Charisma', '15').code).to eq :bad_ability
        end
      end

      describe "focus spells, which the fold does not hold" do
        it "should write an added focus cantrip to the magic object" do
          result = plan('focus', 'Add', 'Cleric', 'Cantrip', 'Heal')

          expect(result.grants).to be_empty
          expect(result.state['magic_ops']).to eq [ { 'op' => 'update', 'charclass' => 'Cleric',
                                                     'info' => { 'focus_cantrip' => { 'divine' => [ 'Heal' ] } } } ]
        end

        it "should revoke a deleted focus spell by kind" do
          result = plan('focus', 'Delete', 'Cleric', 'Spell', 'Heal')

          expect(result.state['magic_ops']).to eq [ { 'op' => 'revoke_focus', 'focus_type' => 'divine',
                                                     'spell' => 'Heal', 'kind' => 'spell' } ]
        end

        it "should refuse a class with no focus type" do
          expect(plan('focus', 'Add', 'Wizard', 'Cantrip', 'Heal').code).to eq :bad_charclass
        end
      end

      describe "a divine font" do
        it "should write the font as the word the rest of the engine compares against" do
          result = plan('divine font', 'Heal')

          expect(result.state['magic_ops']).to eq [ { 'op' => 'update', 'charclass' => 'charclass',
                                                     'info' => { 'divine_font' => [ 'heal' ] } } ]
        end

        it "should refuse a font that is neither heal nor harm" do
          expect(plan('divine font', 'Hurt').code).to eq :bad_font
        end
      end

      describe "alignment and deity, which are not grants" do
        it "should put an alignment in the faith the shell persists" do
          result = plan('alignment', 'CN')

          expect(result.state['faith']['alignment']).to eq 'CN'
          expect(result.grants).to be_empty
        end

        it "should expand a spelled-out alignment" do
          expect(plan('alignment', 'Lawful', 'Good').state['faith']['alignment']).to eq 'LG'
        end

        it "should refuse an alignment the game does not allow" do
          expect(plan('alignment', 'Ce').code).to eq :bad_alignment
        end

        it "should warn when the deity forbids the new alignment" do
          result = AdminSet.plan(state(:faith => { 'deity' => 'Pharasma' }), 'alignment', [ 'CN' ])

          expect(result.messages.map { |m| m['type'] }).to include 'ooc'
        end

        it "should set a deity by its configured name" do
          result = plan('deity', 'Pharasma')

          expect(result.state['faith']['deity']).to eq 'Pharasma'
        end

        it "should refuse a deity the game does not have" do
          expect(plan('deity', 'Cthulhu').code).to eq :bad_deity
        end

        it "should warn when the character's alignment is one the new deity forbids" do
          result = AdminSet.plan(state(:faith => { 'alignment' => 'CN' }), 'deity', [ 'Pharasma' ])

          expect(result.messages.map { |m| m['type'] }).to include 'ooc'
        end
      end

      describe "a value it cannot parse" do
        it "should quote the keyword's own syntax" do
          result = plan('focus', 'Add')

          expect(result.code).to eq :bad_syntax
          expect(result.args['syntax']).to eq '[add|delete] <charclass> [cantrip|spell] <spell name>'
        end

        it "should give every keyword a syntax to quote" do
          expect(AdminSet.targets.reject { |t| AdminSet.syntax(t) }).to eq []
        end
      end

      describe "what it tells the player" do
        it "should name the element it changed" do
          result = plan('skill', 'Arcana', 'Expert')
          message = result.messages.find { |m| m['type'] != 'ooc' }

          expect(message['key']).to eq 'pf2e.updated_ok'
          expect(message['args']).to eq('element' => 'Arcana', 'char' => 'Tester')
        end
      end
    end
  end
end
