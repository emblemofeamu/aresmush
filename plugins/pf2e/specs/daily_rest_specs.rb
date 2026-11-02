require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A night's rest in an encounter: the night's Hit Points, the day's once-a-day uses, and what lasts
    # less than a day ended - for someone as they stand in it, and taken back like any other change.
    describe "a night's rest", :dbtest => true do

      class RestClient
        attr_reader :failures, :said

        def initialize
          @failures = []
          @said = []
        end

        def logged_in?
          true
        end

        def emit_failure(message)
          @failures << message.to_s
        end

        %w{emit_success emit emit_ooc}.each { |name| define_method(name) { |message| @said << message.to_s } }
      end

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @client = RestClient.new
        @room = Room.create(:name => "Camp#{rand(1000000)}")
        @scene = Scene.create(:room => @room)
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @char = Character.create(:name => "Rester#{rand(1000000)}", :room => @room)
        @combat = Pf2eCombat.create(:character => @char, :armor_prof => { 'unarmored' => 'trained' })
        @hp = Pf2eHP.create(:character => @char, :ancestry_hp => 8, :charclass_hp => 10)
        @char.update(:combat => @combat, :hp => @hp, :pf2_level => 3, :pf2_conditions => {}, :pf2_traits => [],
                     :pf2_derived => {}, :pf2_feats => {}, :pf2_base_info => { 'charclass' => 'Fighter' },
                     :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] })
        @abilities = Pf2e::ABILITIES.map { |name| Pf2eAbilities.create(:character => @char, :name => name, :base_val => 14) }
        @encounter = PF2Encounter.create(:scene => @scene, :organizer => @gm.name, :round => 1, :is_active => true)
        Combatants.join(@encounter, @char.name, 10, :holder => Character[@char.id])

        allow_any_instance_of(Room).to receive(:emit_ooc)
        allow(Scenes).to receive(:add_to_scene)
      end

      after(:each) do
        PF2Encounter[@encounter.id]&.delete
        (@abilities + [ @hp, @combat, @char, @gm, @scene, @room ]).each { |one| one&.delete }
      end

      def standing
        CombatantStates.of(PF2Encounter[@encounter.id], Character[@char.id])
      end

      def rest(text = 'e/rest', who = @gm)
        PF2EncounterRestCmd.new(@client, Command.new(text), Character[who.id]).on_command
      end

      it "should make a once-a-day action usable again" do
        TurnState.spend(standing, 'Once A Day', :frequency => { 'max' => 1, 'per' => 'day' })

        rest

        expect(@client.failures).to eq []
        expect(TurnState.used(standing, 'Once A Day')).to eq 0
      end

      it "should leave what is limited per encounter to the encounter" do
        TurnState.spend(standing, 'Once A Fight', :frequency => { 'max' => 1, 'per' => 'PT1M' })

        rest

        expect(TurnState.used(standing, 'Once A Fight')).to eq 1
      end

      # Constitution +2 at 3rd level: 6 Hit Points a night.
      it "should recover the night's Hit Points, in the encounter only" do
        Pf2eHP.modify_damage(standing, 10)

        rest

        expect(standing.damage).to eq 4
        expect(Pf2eHP[@hp.id].damage).to eq 0
      end

      it "should get someone at 0 Hit Points up, and end their dying" do
        full = Pf2eHP.get_max_hp(standing)

        Pf2eHP.modify_damage(standing, full)
        expect(Pf2e.condition_level(standing, 'Dying')).to be_positive

        rest

        expect(Pf2eHP.get_current_hp(standing)).to eq 6
        expect(standing.pf2_conditions.keys & %w{Dying Unconscious}).to eq []
      end

      it "should do nothing for the dead" do
        standing.update(:pf2_is_dead => true, :damage => Pf2eHP.get_max_hp(standing))

        rest

        expect(Pf2eHP.get_current_hp(standing)).to eq 0
      end

      it "should rest as often as the GM says, and be taken back" do
        Pf2eHP.modify_damage(standing, 10)

        rest
        rest
        expect(standing.damage).to eq 0

        History.undo(PF2Encounter[@encounter.id])
        expect(standing.damage).to eq 4
      end

      it "should be the GM's to call" do
        rest('e/rest', @char)

        expect(@client.failures).to eq [ t('pf2e.not_organizer') ]
      end
    end
  end
end
