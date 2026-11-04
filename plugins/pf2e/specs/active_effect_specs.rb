require "plugin_test_loader"

module AresMUSH

  # Effects a character is under for a while.
  #
  # Nothing modelled one: a spell cast spent its slot and applied nothing, and a condition's `duration`
  # was written by nothing and read by nothing. An effect is now a catalogue entry imported from
  # Foundry's effect packs - its rules read the same way a feat's are - and an instance on the character
  # that keeps time with the encounter it began in.
  describe "active effects", :dbtest => true do

    before(:each) do
      bootstrapper = AresMUSH::Bootstrapper.new
      bootstrapper.config_reader.load_game_config
      bootstrapper.db.load_config

      @char = Character.create(:name => "Effect#{rand(1000000)}")
      @combat = Pf2eCombat.create(:character => @char, :perception => 'trained',
                                  :saves => { 'Fortitude' => 'trained', 'Reflex' => 'trained',
                                              'Will' => 'trained' })
      @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
      @char.update(:combat => @combat, :hp => @hp, :pf2_level => 5, :pf2_conditions => {},
                   :pf2_traits => [], :pf2_derived => {}, :pf2_feats => {})
      @abilities = Pf2e::ABILITIES.map { |name|
        Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14)
      }
      @encounters = []
    end

    after(:each) do
      Pf2e::ActiveEffects.on(Character[@char.id]).each(&:delete)
      @encounters.each(&:delete)
      @abilities.each(&:delete)
      @hp&.delete
      @combat&.delete
      @char&.delete
    end

    def reread
      Character[@char.id]
    end

    def apply(name, options = [], encounter = nil)
      Pf2e::ActiveEffects.apply(reread, name, :options => options, :encounter => encounter)
    end

    def perception
      Pf2eCombat.get_perception(reread)
    end

    describe "the catalogue" do
      it "should have been imported" do
        expect(Pf2e::ActiveEffects.catalogue.size).to be > 2000
      end

      # A player types `heroism`, not `Spell Effect: Heroism`.
      it "should find an effect without the prefix Foundry names it with" do
        expect(Pf2e::ActiveEffects.find('heroism').state).to eq 'Spell Effect: Heroism'
      end

      it "should say which it could be when a name matches several" do
        found = Pf2e::ActiveEffects.find('mutagen')

        expect(found.code).to eq :ambiguous
      end

      it "should refuse a name that matches nothing" do
        expect(Pf2e::ActiveEffects.find('zzzz nothing').code).to eq :not_found
      end
    end

    describe "what an effect does" do
      it "should reach every figure it names" do
        plain = perception

        apply('heroism')

        expect(perception).to eq plain + 1
      end

      # Heroism is +1, +2 from 6th rank and +3 from 9th, which is its own formula over `@item.level`.
      it "should read the rank it was cast at" do
        plain = perception

        apply('heroism', [ 'rank 6' ])

        expect(perception).to eq plain + 2
      end

      it "should stop when it ends" do
        plain = perception

        apply('heroism')
        Pf2e::ActiveEffects.remove_named(reread, 'heroism')

        expect(perception).to eq plain
      end

      it "should not stack with itself, since it is a status bonus" do
        plain = perception

        apply('heroism')
        apply('heroism')

        expect(perception).to eq plain + 1
      end
    end

    # Rage: temporary hit points of your level plus your Constitution modifier, which its own write
    # records as a counter and its TempHP rule reads back as `@actor.flags.system.rageTempHP`.
    describe "temporary hit points" do
      it "should give them when the effect begins" do
        apply('rage')

        expect(Pf2eHP[@hp.id].temp_hp).to eq 5 + 2
      end

      it "should take them away when the effect ends" do
        apply('rage')
        Pf2e::ActiveEffects.remove_named(reread, 'rage')

        expect(Pf2eHP[@hp.id].temp_hp).to eq 0
      end

      # They do not stack: the better of what is held and what is given.
      it "should not lower what is already held" do
        @hp.update(:temp_hp => 20)

        apply('rage')

        expect(Pf2eHP[@hp.id].temp_hp).to eq 20
      end

      it "should leave temporary hit points from elsewhere alone when it ends" do
        @hp.update(:temp_hp => 20)

        apply('rage')
        Pf2e::ActiveEffects.remove_named(reread, 'rage')

        expect(Pf2eHP[@hp.id].temp_hp).to eq 20
      end
    end

    describe "what an effect brings with it" do
      it "should bring a condition for as long as it lasts" do
        apply('Apricot of Bestial Might')

        expect(Pf2e.held_conditions(reread)['Clumsy']['granted_by']).to eq 'Effect: Apricot of Bestial Might'
      end

      it "should take it away again when it ends" do
        apply('Apricot of Bestial Might')
        Pf2e::ActiveEffects.remove_named(reread, 'Apricot of Bestial Might')

        expect(Pf2e.held_conditions(reread).keys).to_not include 'Clumsy'
      end
    end

    # An encounter with two in it. `next_init` is who goes next, so after the first advance it is the
    # first participant's turn in round one.
    def encounter(round: 1, turn: 0)
      found = PF2Encounter.create(:participants => [ [ 20.0, @char.name ], [ 10.0, 'Goblin' ] ],
                                  :round => round, :next_init => (turn + 1) % 2, :organizer => 'Staff')
      @encounters << found

      found
    end

    def advance(encounter)
      order = Pf2e::Combatants.all(encounter)
      ending = Pf2e::ActiveEffects.current_turn(encounter)
      ending_round = encounter.round
      moved = Pf2e::Encounters::Turn.move('next', :size => order.size, :at => encounter.next_init,
                                                  :round => encounter.round).state

      encounter.update(:round => moved['round'], :next_init => moved['upcoming'])

      Pf2e::Turns.advanced(encounter, ending, ending_round, order[moved['current']].label, moved['round'])
    end

    describe "keeping time in an encounter" do
      # One round, ending as the applier's next turn starts.
      let(:one_round) { 'Effect: Adamantine Body' }

      # One round, ending as the applier's next turn ends: a +2 circumstance bonus to AC.
      let(:to_turn_end) { 'Effect: +2 circumstance bonus to AC' }

      it "should begin on the turn it was applied in" do
        fight = encounter

        effect = apply(one_round, [], fight).state

        expect(effect.started_round).to eq 1
        expect(effect.started_turn).to eq @char.name
      end

      it "should last through the other turns of the round" do
        fight = encounter
        apply(one_round, [], fight)

        advance(fight)

        expect(Pf2e::ActiveEffects.on(reread).map(&:name)).to eq [ one_round ]
      end

      it "should end as the turn it began on comes round again" do
        fight = encounter
        apply(one_round, [], fight)

        advance(fight)
        ended = advance(fight)

        expect(ended).to eq [ Pf2e::Turns.event('pf2e.effect_ended', 'effect' => one_round, 'name' => @char.name) ]
        expect(Pf2e::ActiveEffects.on(reread)).to eq []
      end

      # `turn-end`: it outlasts the start of that turn, and ends as the turn does.
      it "should end as that turn ends, where the effect says so" do
        fight = encounter
        apply(to_turn_end, [], fight)

        advance(fight)
        advance(fight)

        expect(Pf2e::ActiveEffects.on(reread).map(&:name)).to eq [ to_turn_end ]
        expect(advance(fight)).to eq [ Pf2e::Turns.event('pf2e.effect_ended', 'effect' => to_turn_end,
                                                          'name' => @char.name) ]
      end

      it "should say how long it has left" do
        fight = encounter
        effect = apply(one_round, [], fight).state

        expect(Pf2e::ActiveEffects.remaining(effect)).to include '1'
      end

      # An effect that ends with the turn it began in says so, rather than "0 rounds left".
      it "should say an effect lasting to the end of the turn lasts that long" do
        fight = encounter
        effect = apply('Effect: Bespell Strikes', [], fight).state

        expect(Pf2e::ActiveEffects.remaining(effect)).to eq t('pf2e.effect_lasts_turn_end')
      end

      # A minute is ten rounds, and each round here is two turns. Rage lasts a minute.
      it "should count a minute in rounds" do
        fight = encounter
        apply('rage', [], fight)

        19.times { advance(fight) }

        expect(Pf2e::ActiveEffects.on(reread).map(&:name)).to eq [ 'Effect: Rage' ]

        advance(fight)

        expect(Pf2e::ActiveEffects.on(reread)).to eq []
      end
    end

    describe "when the encounter ends" do
      it "should end what could not outlast it" do
        fight = encounter
        apply('heroism', [], fight)

        Pf2e::ActiveEffects.encounter_ended(fight)

        expect(Pf2e::ActiveEffects.on(reread)).to eq []
      end

      it "should leave what lasts hours" do
        fight = encounter
        apply('Aurochs Jerky', [], fight)

        Pf2e::ActiveEffects.encounter_ended(fight)

        expect(Pf2e::ActiveEffects.on(reread).size).to eq 1
      end
    end

    # What brought an effect is kept with it, and its rules read it under `parent:origin`.
    describe "what brought it" do
      def antidote(origin)
        Pf2e::ActiveEffects.apply(reread, 'Effect: Antidote', :origin => origin)
      end

      def antidote_options
        Pf2e::ActiveEffects.sources(reread).find { |one| one['name'] == 'Effect: Antidote' }['options']
      end

      it "should keep the item it came from" do
        antidote(Pf2e::Consumables.item_origin('Antidote (Major)', Pf2e::Consumables.info('Antidote (Major)')))

        expect(Pf2e::ActiveEffects.on(reread).first.origin['item']['name']).to eq 'Antidote (Major)'
      end

      it "should answer its own choice from that item" do
        antidote(Pf2e::Consumables.item_origin('Antidote (Major)', Pf2e::Consumables.info('Antidote (Major)')))

        expect(antidote_options).to include('parent:origin:item:slug:antidote-major', 'antidote:antidote-major')
      end

      it "should leave the choice open when nothing said where it came from" do
        antidote(nil)

        expect(antidote_options.grep(/\Aantidote:/)).to be_empty
      end
    end

    describe "a night's rest" do
      it "should end anything shorter than a day" do
        apply('Aurochs Jerky')

        Pf2e::ActiveEffects.rested(reread)

        expect(Pf2e::ActiveEffects.on(reread)).to eq []
      end

      it "should count a night off something measured in days" do
        effect = apply('Living Epic').state
        nights = effect.rests_left

        Pf2e::ActiveEffects.rested(reread)

        remaining = Pf2e::ActiveEffects.on(reread)

        if nights > 1
          expect(remaining.first.rests_left).to eq nights - 1
        else
          expect(remaining).to eq []
        end
      end

      it "should leave what lasts until it is ended" do
        unlimited = Pf2e::ActiveEffects.catalogue.find { |_name, info|
          info['duration']['unit'] == 'unlimited'
        }.first

        apply(unlimited)
        Pf2e::ActiveEffects.rested(reread)

        expect(Pf2e::ActiveEffects.on(reread).map(&:name)).to eq [ unlimited ]
      end
    end
  end
end
