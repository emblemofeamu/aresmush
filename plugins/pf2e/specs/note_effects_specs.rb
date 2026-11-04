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
                       pf2e_feat_ancestry pf2e_feat_class pf2e_feat_general pf2e_feat_skill pf2e_magicitem pf2e_weapons}.flat_map do |name|
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

        it "should offer an effect the player chooses, by the command that applies it" do
          bomb = { 'source' => 'Debilitating Bomb', 'text' => 'The target must succeed...', 'outcome' => %w{success},
                   'effects' => [ 'Effect: Debilitating Bomb' ] }
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ bomb ], out, :degree => Degree::SUCCESS)

          expect(out['lines']).to include('pf2e.act_note_effect Effect: Debilitating Bomb | effect/add Goblin=Effect: Debilitating Bomb')
        end

        # A note with no outcome holds whatever happened, so nothing says the effect's moment came.
        it "should offer, not apply, an effect from a note that names no outcome" do
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ sympathetic.merge('outcome' => []) ], out, :degree => Degree::SUCCESS)

          expect(out['lines'].grep(/act_note_effect/).size).to eq 1
        end

        it "should leave an effect the roll already put on" do
          expect(ActiveEffects).not_to receive(:apply)

          NoteEffects.tell(scene, [ sympathetic ], out, :degree => Degree::SUCCESS, :done => [ 'Effect: Sympathetic Strike' ])

          expect(out['lines'].grep(/act_now_under|act_note_effect/)).to eq []
        end
      end
    end
  end
end
