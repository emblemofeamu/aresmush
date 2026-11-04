require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What an effect's own rules see of the effect, under `parent:`.
    #
    # 205 of the effects we stock test `parent:badge:value`, `parent:level`, `parent:origin:*` or
    # `parent:context:check:outcome`, and nothing said any of them: every such statement was false, so
    # Ancestral Geometry never chose a save, Devouring Dark Form never offered a shark, and an antidote
    # could not tell which antidote it came from.
    describe "parent roll options" do

      let(:effects) do
        YAML.load_file(File.join(AresMUSH.game_path, 'config', 'pf2e_effects.yml'))['pf2e_effects']
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_effects').and_return(effects)
      end

      def instance(level: 1, badge: nil, origin: {})
        double('Pf2eEffect', id: 42, level: level, badge: badge, origin: origin)
      end

      def options_for(name, **said)
        ActiveEffects.parent_options(name, instance(**said))
      end

      def rules_of(name)
        effects[name]['rules']
      end

      describe "the effect itself" do
        it "should name the effect, its type and its level" do
          found = options_for('Effect: Antidote', level: 3)

          expect(found).to include('parent:id:42', 'parent:slug:effect-antidote', 'parent:effect-antidote',
                                   'parent:type:effect', 'parent:level:3')
        end

        it "should give its badge where it has one, and nothing where it has none" do
          expect(options_for('Effect: Antidote', badge: 2)).to include('parent:badge:value:2')
          expect(options_for('Effect: Antidote').grep(/badge/)).to be_empty
        end

        # Ancestral Geometry's save is its badge: 1 Fortitude, 2 Reflex, 3 Will.
        it "should let a rule keyed to the badge apply" do
          reflex = rules_of('Effect: Ancestral Geometry (Save Type)').find { |row| row['value'] == 'reflex' }

          expect(Predicate.test(reflex['predicate'], options_for('Effect: Ancestral Geometry (Save Type)', badge: 2))).to be true
          expect(Predicate.test(reflex['predicate'], options_for('Effect: Ancestral Geometry (Save Type)', badge: 1))).to be false
        end

        # Devouring Dark Form's shark is a 2nd-rank choice.
        it "should let a comparison read the effect's level" do
          set = rules_of('Spell Effect: Devouring Dark Form').find { |row| row['key'] == 'ChoiceSet' }
          shark = set['choices'].find { |one| one['value'] == 'shark' }

          expect(Predicate.test(shark['predicate'], options_for('Spell Effect: Devouring Dark Form', level: 2))).to be true
          expect(Predicate.test(shark['predicate'], options_for('Spell Effect: Devouring Dark Form', level: 1))).to be false
        end

        it "should say nothing for a catalogue entry that is not an instance" do
          expect(ActiveEffects.parent_options('Effect: Antidote', nil)).to eq []
        end
      end

      describe "what brought it" do
        def major_antidote
          ActiveEffects.origin(item: { 'name' => 'Antidote (Major)', 'type' => 'consumable', 'level' => 18,
                                       'traits' => %w{alchemical elixir} })
        end

        it "should name the item that brought it" do
          found = options_for('Effect: Antidote', origin: major_antidote)

          expect(found).to include('parent:origin:item', 'parent:origin:item:slug:antidote-major',
                                   'parent:origin:item:antidote-major', 'parent:origin:item:type:consumable',
                                   'parent:origin:item:level:18', 'parent:origin:item:trait:elixir')
        end

        it "should name the creature that used it" do
          caster = double('Character', pf2_level: 7, pf2_traits: [ 'Elf', 'Humanoid' ])
          origin = ActiveEffects.origin(item: { 'name' => 'Heroism', 'type' => 'spell', 'level' => 3 }, by: caster)

          expect(options_for('Spell Effect: Heroism', origin: origin))
            .to include('parent:origin:level:7', 'parent:origin:trait:elf', 'parent:origin:item:level:3')
        end

        # Aldori Swordlord's temporary hit points are 10 on a critical hit and 5 on a hit.
        it "should give the outcome of the check that brought it" do
          origin = ActiveEffects.origin(item: { 'name' => 'Strike' }, outcome: Degree::CRITICAL_SUCCESS)
          set = rules_of('Effect: Aldori Swordlord (Temporary Hit Points)').find { |row| row['key'] == 'ChoiceSet' }
          held = options_for('Effect: Aldori Swordlord (Temporary Hit Points)', origin: origin)

          fitting = set['choices'].select { |one| Predicate.test(one['predicate'], held) }.map { |one| one['value'] }

          expect(held).to include('parent:context:check:outcome:3')
          expect(fitting).to eq [ 10 ]
        end

        it "should leave out what it was not told" do
          expect(ActiveEffects.origin).to eq({})
          expect(options_for('Effect: Antidote').grep(/origin|context/)).to be_empty
        end
      end

      # A choice whose circumstances name what brought the effect is answered by them when only one
      # holds, so the player is not asked which antidote they drank.
      describe "a choice the origin answers" do
        let(:char) { double('Character') }

        before(:each) do
          allow(Effects).to receive(:character_facts).with(char).and_return([])
        end

        def built(origin)
          effect = instance(origin: origin)
          source = Effects.source('Effect: Antidote', rules_of('Effect: Antidote'),
                                  'chosen' => [],
                                  'options' => ActiveEffects.parent_options('Effect: Antidote', effect))

          Effects.with_selections(char, source)
        end

        it "should pick the one choice that fits" do
          origin = ActiveEffects.origin(item: { 'name' => 'Antidote (Major)' })

          expect(built(origin)['options']).to include('antidote:antidote-major')
        end

        it "should pick nothing when every choice fits" do
          expect(built({})['options'].grep(/\Aantidote:/)).to be_empty
        end

        it "should let the bonus the choice names apply" do
          source = built(ActiveEffects.origin(item: { 'name' => 'Antidote (Major)' }))
          upgrade = Rules.of_kind(source, 'AdjustModifier').find { |row| row['value'] == 4 }

          expect(Predicate.test(upgrade['predicate'], source['options'])).to be true
        end

        it "should still ask a set whose choices are about something else" do
          set = { 'choices' => [ { 'value' => 'fire', 'when' => [ 'self:level:1' ] },
                                 { 'value' => 'cold', 'when' => [ 'self:level:2' ] } ] }

          expect(Effects.only_fitting(set, [ 'self:level:1' ])).to be_nil
        end
      end
    end
  end
end
