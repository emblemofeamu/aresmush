require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Every character change is a pure transformation run through one service:
    #   state + action -> Ok(new state, grants, messages) | Err(code, locale key, args)
    describe Outcome do
      describe "the union" do
        it "should report Ok as ok and not err" do
          result = Ok.new(:state => { 'level' => 2 })

          expect(result.ok?).to be true
          expect(result.err?).to be false
          expect(result.state['level']).to eq 2
        end

        it "should report Err as err and carry a code, a locale key and args" do
          result = Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'ancestry')

          expect(result.err?).to be true
          expect(result.code).to eq :bad_option
          expect(result.key).to eq 'pf2e.bad_option'
          expect(result.args['element']).to eq 'ancestry'
        end

        it "should support pattern matching on the Ok branch" do
          matched = case Ok.new(:state => { 'level' => 5 })
                    in Ok(state:) then "ok at level #{state['level']}"
                    in Err(code:) then "err #{code}"
                    end

          expect(matched).to eq "ok at level 5"
        end

        it "should support pattern matching on the Err branch" do
          matched = case Err.new(:locked, 'pf2e.locked')
                    in Ok(state:) then "ok"
                    in Err(code:) then "err #{code}"
                    end

          expect(matched).to eq "err locked"
        end
      end

      describe "revocations" do
        it "should let a transformation ask for an earlier grant to be undone" do
          result = Ok.new(:state => {}).with_revocation('add_language', 'language' => 'Kamin')

          expect(result.revocations.first['kind']).to eq 'add_language'
          expect(result.revocations.first['match']['language']).to eq 'Kamin'
        end

        it "should accumulate revocations across a chain" do
          result = Ok.new(:state => {}).with_revocation('add_language', 'language' => 'Kamin')
            .and_then { |state| Ok.new(:state => state).with_revocation('raise_skill', 'skill' => 'Arcana') }

          expect(result.revocations.map { |r| r['kind'] }).to eq [ 'add_language', 'raise_skill' ]
        end
      end

      describe :and_then do
        it "should pass the new state to the next step" do
          result = Ok.new(:state => { 'level' => 1 }).and_then { |state| Ok.new(:state => state.merge('level' => 2)) }

          expect(result.state['level']).to eq 2
        end

        it "should accumulate grants and messages across steps" do
          result = Ok.new(:state => {}, :grants => [ 'a' ], :messages => [ { 'key' => 'one' } ])
            .and_then { |state| Ok.new(:state => state, :grants => [ 'b' ], :messages => [ { 'key' => 'two' } ]) }

          expect(result.grants).to eq [ 'a', 'b' ]
          expect(result.messages.map { |m| m['key'] }).to eq [ 'one', 'two' ]
        end

        it "should short-circuit on the first error" do
          ran = false
          result = Ok.new(:state => {})
            .and_then { |_state| Err.new(:nope, 'pf2e.nope') }
            .and_then { |_state| ran = true; Ok.new(:state => {}) }

          expect(result.err?).to be true
          expect(ran).to be false
        end
      end
    end

    describe Ledger do
      describe :matching_grants do
        def row(seq, kind, payload, reverted = nil)
          { 'seq' => seq, 'txn' => "t#{seq}", 'kind' => kind, 'payload' => payload, 'source_type' => 'chargen', 'effective_level' => 1, 'reverted_by' => reverted }
        end

        it "should find a live grant whose payload matches every pair" do
          rows = [ row(1, 'add_language', { 'language' => 'Kamin' }), row(2, 'add_language', { 'language' => 'Silya' }) ]

          found = Ledger.matching_grants(rows, 'add_language', 'language' => 'Silya')

          expect(found.map { |g| g['seq'] }).to eq [ 2 ]
        end

        it "should ignore grants of another kind" do
          rows = [ row(1, 'raise_skill', { 'skill' => 'Arcana' }) ]

          expect(Ledger.matching_grants(rows, 'add_language', 'language' => 'Arcana')).to eq []
        end

        it "should ignore grants that are already reverted" do
          rows = [ row(1, 'add_language', { 'language' => 'Kamin' }, 'earlier-rollback') ]

          expect(Ledger.matching_grants(rows, 'add_language', 'language' => 'Kamin')).to eq []
        end

        it "should match case-insensitively, the way players type" do
          rows = [ row(1, 'add_language', { 'language' => 'Kamin' }) ]

          expect(Ledger.matching_grants(rows, 'add_language', 'language' => 'kamin').size).to eq 1
        end
      end
    end

    describe CharacterService do
      before do
        @state = CharState.build({
            'level' => 1,
            'baseinfo_locked' => true,
            'boosts_working' => { 'free' => [ 'open', 'open' ] }
          },
          :config => ConfigView.fixture({})
        )
      end

      it "should refuse an action it does not know" do
        result = CharacterService.call(@state, :summon_ancient_horror)

        expect(result.err?).to be true
        expect(result.code).to eq :unknown_action
      end

      it "should list its actions" do
        expect(CharacterService.actions).to include :set_base_info
        expect(CharacterService.actions).to include :set_boost
      end

      it "should run a chain of actions and hand each the previous state" do
        result = CharacterService.chain(@state, [
          [ :set_boost, { 'type' => 'free', 'ability' => 'Strength' } ],
          [ :set_boost, { 'type' => 'free', 'ability' => 'Wisdom' } ]
        ])

        expect(result.ok?).to be true
        expect(result.state['boosts_working']['free']).to eq [ 'Strength', 'Wisdom' ]
      end

      it "should stop a chain at the first error and report which action failed" do
        result = CharacterService.chain(@state, [
          [ :set_boost, { 'type' => 'free', 'ability' => 'Strength' } ],
          [ :set_boost, { 'type' => 'free', 'ability' => 'NotAnAbility' } ],
          [ :set_boost, { 'type' => 'free', 'ability' => 'Wisdom' } ]
        ])

        expect(result.err?).to be true
        expect(result.code).to eq :bad_option
        expect(result.failed_action).to eq :set_boost
      end
    end

    describe CharState do
      it "should build a string-keyed state from character data and a sheet" do
        state = CharState.build({
            'base_info' => { 'ancestry' => 'Khazad' },
            'level' => 3,
            'baseinfo_locked' => true
          },
          :sheet => { 'skills' => { 'Arcana' => 'expert' } },
          :config => ConfigView.fixture('pf2e' => { 'max_level' => 20 })
        )

        expect(state['base_info']['ancestry']).to eq 'Khazad'
        expect(state['level']).to eq 3
        expect(state['locks']['baseinfo']).to be true
        expect(state['sheet']['skills']['Arcana']).to eq 'expert'
        expect(state['config'].read('pf2e', 'max_level')).to eq 20
      end

      it "should default every collection so a core never guards against nil" do
        state = CharState.build({}, :sheet => nil, :config => ConfigView.fixture({}))

        expect(state['base_info']).to eq({})
        expect(state['to_assign']).to eq({})
        expect(state['boosts_working']).to eq({})
        expect(state['sheet']['skills']).to eq({})
        expect(state['level']).to eq 1
      end

      describe :diff_attrs do
        it "should name only the character attributes a transformation changed" do
          before_state = CharState.build({ 'base_info' => { 'ancestry' => '' }, 'level' => 1 }, :config => ConfigView.fixture({}))
          after_state = before_state.merge('base_info' => { 'ancestry' => 'Khazad' })

          expect(CharState.diff_attrs(before_state, after_state)).to eq({ 'pf2_base_info' => { 'ancestry' => 'Khazad' } })
        end

        it "should map the lock flags back to their own attributes" do
          before_state = CharState.build({}, :config => ConfigView.fixture({}))
          after_state = before_state.merge('locks' => before_state['locks'].merge('baseinfo' => true))

          expect(CharState.diff_attrs(before_state, after_state)).to eq({ 'pf2_baseinfo_locked' => true })
        end

        it "should return nothing when the state did not move" do
          state = CharState.build({ 'level' => 4 }, :config => ConfigView.fixture({}))

          expect(CharState.diff_attrs(state, state)).to eq({})
        end

        it "should ignore the config and the derived sheet, which are not stored" do
          before_state = CharState.build({}, :sheet => { 'skills' => {} }, :config => ConfigView.fixture({}))
          after_state = before_state.merge('sheet' => { 'skills' => { 'Arcana' => 'expert' } }, 'config' => ConfigView.fixture('x' => 1))

          expect(CharState.diff_attrs(before_state, after_state)).to eq({})
        end
      end
    end

    describe ConfigView do
      it "should read a nested fixture path" do
        view = ConfigView.fixture('pf2e_class' => { 'Wizard' => { 'HP' => 6 } })

        expect(view.read('pf2e_class', 'Wizard', 'HP')).to eq 6
      end

      it "should return nil for a missing path instead of raising" do
        expect(ConfigView.fixture({}).read('pf2e_class', 'Wizard')).to be_nil
      end

      it "should return nil when a mid-path value is not a hash" do
        view = ConfigView.fixture('pf2e' => { 'max_level' => 20 })

        expect(view.read('pf2e', 'max_level', 'nope')).to be_nil
      end
    end
  end
end
