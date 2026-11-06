require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A roll's notes and the effects they link (`NoteEffects`, `pf2e_note_effects.yml`).
    describe "note effects" do

      # Read once: the catalogues are large.
      def self.config(name)
        @read ||= {}
        @read[name] ||= YAML.load_file(File.join(AresMUSH.game_path, 'config', "#{name}.yml")).values.first
      end

      # Every effect any Note row of ours links. Only the catalogues with Note rows are read.
      def self.linked
        @linked ||= %w{pf2e_actions pf2e_armor pf2e_class_features pf2e_conditions pf2e_consumables pf2e_effects
                       pf2e_feat_ancestry pf2e_feat_class pf2e_feat_general pf2e_feat_skill pf2e_magicitem pf2e_weapons
                       pf2e_runes}.flat_map do |name|
          config(name).values.select { |entry| entry.is_a?(Hash) }.flat_map do |entry|
            Array(entry['rules']).select { |row| row.is_a?(Hash) && row['key'] == 'Note' }.flat_map { |row| Array(row['effects']) }
          end
        end.uniq
      end

      let(:effects) { self.class.config('pf2e_effects') }
      let(:table) { self.class.config('pf2e_note_effects') }
      let(:linked) { self.class.linked }

      describe "the data" do
        it "should stock every effect a note links" do
          expect(linked).not_to be_empty
          expect(linked.reject { |name| effects.key?(name) }).to eq []
        end

        it "should say who every linked effect is for, but Divine Rebuttal's" do
          expect(linked - table.keys).to eq [ 'Effect: Divine Rebuttal' ]
        end

        it "should name only effects we stock, each for the target or the one who rolled" do
          expect(table.keys.reject { |name| effects.key?(name) }).to eq []
          expect(table.values.map { |entry| entry['for'] }.uniq.sort).to eq %w{self target}
        end

        # Applying one that asks a question nobody can answer from the roll would leave it unanswered.
        it "should apply only effects whose every choice the roll answers" do
          applied = table.select { |_name, entry| entry['apply'] }.keys

          expect(applied).not_to be_empty
          applied.each do |name|
            Array(effects[name]['rules']).select { |row| row['key'] == 'ChoiceSet' }.each do |set|
              expect(Array(set['choices']).all? { |one| one['predicate'].to_json.include?('parent:') }).to be(true), name
            end
          end
        end
      end

      describe "telling" do
        let(:actor) { double('actor', :holder => double('Character', :id => 1, :pf2_level => 4, :pf2_traits => [ 'human' ]), :label => 'Aria') }
        let(:target) { double('target', :holder => double('Character', :id => 2), :label => 'Goblin') }
        let(:scene) { Acting::Scene.new(nil, actor, target, nil, true) }
        let(:out) { Acting.report }

        let(:sympathetic) do
          { 'source' => 'Sympathetic Strike', 'text' => 'Until the beginning of your next turn...',
            'outcome' => %w{success criticalSuccess}, 'effects' => [ 'Effect: Sympathetic Strike' ] }
        end

        before(:each) do
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_note_effects').and_return(table)
          allow(Global).to receive(:read_config).with('pf2e_effects').and_return(effects)
          allow(Acting).to receive(:told) { |key, args = {}| "#{key} #{args.values.join(' | ')}" }
          allow(ActiveEffects).to receive(:remaining).and_return('1 round')
        end

        def put_on
          made = nil
          expect(ActiveEffects).to receive(:apply) do |holder, name, **said|
            made = { 'holder' => holder, 'name' => name, 'origin' => said[:origin] }
            Ok.new(:state => double('effect', :name => name))
          end

          yield

          made
        end

        it "should put Sympathetic Strike's effect on whoever was hit, saying what hit them" do
          made = put_on { NoteEffects.tell(scene, [ sympathetic ], out, :degree => Degree::SUCCESS) }

          expect(made['holder']).to be target.holder
          expect(made['origin']).to eq('item' => { 'name' => 'Sympathetic Strike' },
                                       'actor' => { 'level' => 4, 'traits' => [ 'human' ] }, 'outcome' => Degree::SUCCESS)
          expect(out['lines']).to include('pf2e.act_note Until the beginning of your next turn...',
                                          'pf2e.act_now_under Goblin | Effect: Sympathetic Strike | 1 round')
        end

        # The outcome it was brought by is what its own choice reads: -1 on a hit, -2 on a critical hit.
        it "should take the penalty its outcome gives" do
          set = effects['Effect: Sympathetic Strike']['rules'].find { |row| row['key'] == 'ChoiceSet' }
          by = lambda do |degree|
            origin = put_on { NoteEffects.tell(scene, [ sympathetic ], Acting.report, :degree => degree) }['origin']
            held = ActiveEffects.parent_options('Effect: Sympathetic Strike',
                                                double('Pf2eEffect', id: 1, level: 4, badge: nil, origin: origin))

            Effects.only_fitting({ 'choices' => set['choices'].map { |one| { 'when' => one['predicate'], 'value' => one['value'] } } }, held)
          end

          expect(by.call(Degree::SUCCESS)).to eq(-1)
          expect(by.call(Degree::CRITICAL_SUCCESS)).to eq(-2)
        end

        it "should put Panache on whoever rolled" do
          panache = { 'source' => 'Panache', 'text' => 'You gain Panache.', 'outcome' => %w{success}, 'effects' => [ 'Effect: Panache' ] }

          made = put_on { NoteEffects.tell(scene, [ panache ], out, :degree => Degree::SUCCESS) }

          expect(made['holder']).to be actor.holder
        end

        # `effect/add` is the GM's to use, so the command goes to them and not to the room.
        it "should offer the GM an effect the player chooses, by the command that applies it" do
          bomb = { 'source' => 'Debilitating Bomb', 'text' => 'The target must succeed...', 'outcome' => %w{success},
                   'effects' => [ 'Effect: Debilitating Bomb' ] }
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ bomb ], out, :degree => Degree::SUCCESS)

          expect(out['gm']).to eq [ 'pf2e.act_note_effect Effect: Debilitating Bomb | effect/add Goblin=Effect: Debilitating Bomb' ]
          expect(out['lines']).to eq [ 'pf2e.act_note The target must succeed...' ]
        end

        # A note with no outcome holds whatever happened, so nothing says the effect's moment came.
        it "should offer, not apply, an effect from a note that names no outcome" do
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ sympathetic.merge('outcome' => []) ], out, :degree => Degree::SUCCESS)

          expect(out['gm'].grep(/act_note_effect/).size).to eq 1
        end

        # Divine Rebuttal's effect is for every ally, so the table leaves it out and nobody is offered it.
        it "should neither apply nor offer an effect the table leaves out, and still tell the note" do
          rebuttal = { 'source' => 'Divine Rebuttal', 'text' => 'Your allies gain...', 'outcome' => %w{success},
                       'effects' => [ 'Effect: Divine Rebuttal' ] }
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ rebuttal ], out, :degree => Degree::SUCCESS)

          expect(out['lines']).to eq [ 'pf2e.act_note Your allies gain...' ]
          expect(out['gm']).to eq []
        end

        # Raven's review of #8: a note for critical hits only came out on every hit.
        it "should not apply an effect from a note for other outcomes than the roll's" do
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ sympathetic.merge('outcome' => %w{criticalSuccess}) ], out, :degree => Degree::SUCCESS)

          expect(out['lines'].grep(/act_now_under/)).to eq []
        end

        describe "a Strike's damage notes" do
          let(:critical_only) { sympathetic.merge('text' => 'When you critically hit...', 'outcome' => %w{criticalSuccess}) }
          let(:always) { { 'source' => 'Frost Vial', 'text' => 'The target is slowed.', 'outcome' => [], 'effects' => [] } }
          let(:striker) { double('Character') }

          before(:each) do
            allow(Domains).to receive(:for).and_return([ 'damage' ])
            allow(Effects).to receive(:options).and_return([])
            allow(Effects).to receive(:sources).and_return([])
            allow(Pf2eCombat).to receive(:attack_options).and_return([])
            allow(Rules).to receive(:notes).and_return([ critical_only, always ])
          end

          it "should keep a critical hit's notes off an ordinary hit" do
            expect(Damage.notes(striker, {}, [], Degree::SUCCESS)).to eq [ always ]
            expect(Damage.notes(striker, {}, [], Degree::CRITICAL_SUCCESS)).to eq [ critical_only, always ]
          end

          it "should neither tell nor apply a critical hit's note on an ordinary hit" do
            expect(ActiveEffects).not_to receive(:apply)

            NoteEffects.tell(scene, Damage.notes(striker, {}, [], Degree::SUCCESS), out, :degree => Degree::SUCCESS)

            expect(out['lines'].grep(/critically hit/)).to eq []
            expect((out['lines'] + out['gm']).grep(/act_now_under|act_note_effect/)).to eq []
            expect(out['lines']).to include('pf2e.act_note The target is slowed.')
          end

          it "should tell and apply it on a critical hit" do
            made = put_on do
              NoteEffects.tell(scene, Damage.notes(striker, {}, [], Degree::CRITICAL_SUCCESS), out, :degree => Degree::CRITICAL_SUCCESS)
            end

            expect(made['holder']).to be target.holder
            expect(out['lines']).to include('pf2e.act_note When you critically hit...')
          end
        end

        it "should leave an effect the roll already put on" do
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ sympathetic ], out, :degree => Degree::SUCCESS, :done => [ 'Effect: Sympathetic Strike' ])

          expect((out['lines'] + out['gm']).grep(/act_now_under|act_note_effect/)).to eq []
        end
      end

      # A property rune's words come with its own weapon's roll, and no other's.
      describe "a property rune's note" do
        let(:weapon) { double('weapon', :id => 77, :wp_damage => '1d8') }
        let(:source) { Effects.rune_source(weapon, 'crushing') }

        it "should show with its weapon's damage on a critical hit, linking its effect" do
          notes = Rules.notes([ source ], [ '77-damage' ], [])

          expect(notes.size).to eq 1
          expect(notes.first['outcome']).to eq [ 'criticalSuccess' ]
          expect(notes.first['effects']).to eq [ 'Effect: Crushing' ]
          expect(notes.first['text']).to start_with('When you critically hit')
        end

        it "should not show with another weapon's damage" do
          expect(Rules.notes([ source ], [ '78-damage' ], [])).to eq []
        end

        # Raven's review of #9: an ordinary Longsword hit told Crushing's note and put Effect: Crushing on
        # the goblin. 42 of the 53 rune notes are for critical hits only.
        describe "on a Strike" do
          let(:actor) { double('actor', :holder => double('Character', :id => 1, :pf2_level => 4, :pf2_traits => [ 'human' ]), :label => 'Aria') }
          let(:target) { double('target', :holder => double('Character', :id => 2), :label => 'Goblin Warrior #2') }
          let(:scene) { Acting::Scene.new(nil, actor, target, nil, true) }
          let(:out) { Acting.report }

          before(:each) do
            allow(Global).to receive(:read_config).and_call_original
            allow(Global).to receive(:read_config).with('pf2e_note_effects').and_return(table)
            allow(Acting).to receive(:told) { |key, args = {}| "#{key} #{args.values.join(' | ')}" }
            allow(ActiveEffects).to receive(:remaining).and_return('1 round')
            allow(Domains).to receive(:for).and_return([ '77-damage' ])
            allow(Effects).to receive(:options).and_return([])
            allow(Effects).to receive(:sources).and_return([ source ])
            allow(Pf2eCombat).to receive(:attack_options).and_return([])
          end

          def strike(degree)
            NoteEffects.tell(scene, Damage.notes(actor.holder, {}, [], degree), out, :degree => degree)
          end

          it "should neither tell Crushing's note nor apply its effect on an ordinary hit" do
            expect(ActiveEffects).not_to receive(:apply)

            strike(Degree::SUCCESS)

            expect(out['lines']).to eq []
          end

          it "should tell it and put Effect: Crushing on the target on a critical hit" do
            expect(ActiveEffects).to receive(:apply).with(target.holder, 'Effect: Crushing', anything)
                                                    .and_return(Ok.new(:state => double('effect', :name => 'Effect: Crushing')))

            strike(Degree::CRITICAL_SUCCESS)

            expect(out['lines'].first).to include('When you critically hit')
            expect(out['lines']).to include('pf2e.act_now_under Goblin Warrior #2 | Effect: Crushing | 1 round')
          end
        end
      end
    end
  end
end
