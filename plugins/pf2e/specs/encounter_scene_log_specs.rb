require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An encounter is played in its scene: what it says goes to the scene's room and the scene's log,
    # wherever its GM is when they say it, and it ends when its scene stops.
    describe "an encounter in its scene's log", :dbtest => true do

      class SceneLogClient
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

        @client = SceneLogClient.new
        @room = Room.create(:name => "Hall#{rand(1000000)}")
        @elsewhere = Room.create(:name => "Office#{rand(1000000)}")
        @scene = Scene.create(:room => @room, :title => 'The Hall')
        @room.update(:scene => @scene)
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        @encounter = PF2Encounter.create(:scene => @scene, :owner => @gm, :organizer => @gm.name, :round => 1,
                                         :is_active => true)

        @logged = []
        @heard = Hash.new { |hash, key| hash[key] = [] }
        @ooc = []
        allow(Scenes).to receive(:add_to_scene) do |scene, message, _who = nil, _set = nil, ooc = nil|
          @logged << [ scene.id, message.to_s ]
          @ooc << message.to_s if ooc
        end
        allow_any_instance_of(Room).to receive(:emit) { |room, message| @heard[room.id] << message.to_s }
        allow(Global).to receive(:notifier).and_return(double(:notify_ooc => nil))
        allow_any_instance_of(Character).to receive(:is_admin?).and_return(true)
      end

      after(:each) do
        [ PF2Encounter[@encounter.id], @gm, Scene[@scene.id], @room, @elsewhere ].compact.each(&:delete)
      end

      def run(text)
        command = Command.new(text)
        Pf2e.get_cmd_handler(nil, command, nil).new(@client, command, Character[@gm.id]).on_command
      end

      it "should tell the scene its encounter ended, though its GM is elsewhere" do
        @gm.update(:room => @elsewhere)
        run("e/end #{@encounter.id}")

        expect(@client.failures).to eq []
        expect(@heard[@room.id].join).to include("END OF ENCOUNTER #{@encounter.id}")
        expect(@logged).to include([ @scene.id, a_string_including(t('pf2e.encounter_complete', :id => @encounter.id)) ])
      end

      it "should log setting cover in the scene as OOC" do
        run("e/add goblin warrior")
        run('e/cover #1=standard')

        expect(@logged.map(&:last)).to include(a_string_including('cover: standard'))
        expect(@ooc).to include(a_string_including('cover: standard'))
      end

      it "should end an encounter still running when its scene stops, and say so in the scene" do
        allow(Login).to receive(:find_game_client).and_return(nil)
        allow(Global).to receive(:client_monitor).and_return(double(:notify_web_clients => nil))
        allow(Scenes).to receive(:new_scene_activity)
        allow(Scenes).to receive(:participated_in_scene?).and_return(false)
        Scenes.stop_scene(Scene[@scene.id], Character[@gm.id])

        expect(PF2Encounter[@encounter.id].is_active).to be false
        expect(@logged.map(&:last).join).to include(t('pf2e.encounter_ended_with_scene', :id => @encounter.id))
        expect(@heard[@room.id].join).to include(t('pf2e.encounter_ended_with_scene', :id => @encounter.id))
        expect(EncounterLog.lines(PF2Encounter[@encounter.id]).last.last(2)).to eq [ 'end', { 'id' => @encounter.id, 'with_scene' => true } ]
      end

      # The end as the game client shows it: centered, between the lines the start banner has.
      it "should set the end between the start banner's lines, centered" do
        run("e/end #{@encounter.id}")

        told = @heard[@room.id].join
        expect(told).to start_with('%lh%r').and end_with('%r%lf')
        expect(told).to match(/%r {10,}\S*\*\*\* END OF ENCOUNTER/)
      end
    end
  end
end
