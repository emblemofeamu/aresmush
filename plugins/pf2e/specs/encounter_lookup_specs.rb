require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The keys whose whole record was asked for while recording, by this thread. `ReadCache` is prepended
    # to Redic, which `allow_any_instance_of` won't stub, so this listens at the client under it.
    module RecordsLoaded
      KEY = :pf2e_records_loaded

      def write(args)
        Thread.current[KEY] << args[1].to_s if Thread.current[KEY] && args.first.to_s.casecmp?('HGETALL')
        super
      end
    end
    Redic::Client.prepend(RecordsLoaded) unless Redic::Client < RecordsLoaded

    # Finding the encounter that is running reads that one, however many a scene, a GM or a character
    # has had before: the running ones are kept in an index of their own.
    describe "finding a running encounter", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @gm = Character.create(:name => "Gm#{rand(1000000)}")
        @hero = Character.create(:name => "Hero#{rand(1000000)}")
        @scene = Scene.create
        @ended = 4.times.map do
          PF2Encounter.create(:organizer => @gm.name, :owner => @gm, :scene => @scene).tap do |one|
            @hero.encounters.add(one)
            one.update(:is_active => false)
          end
        end
        @running = PF2Encounter.create(:organizer => @gm.name, :owner => @gm, :scene => @scene)
        Combatants.join(@running, @hero.name, 10, :holder => Character[@hero.id])
        @hero.encounters.add(@running)
        PF2Encounter.indexed!
      end

      after(:each) do
        (@ended + [ @running ]).each { |one| PF2Encounter[one.id]&.delete }
        [ @gm, @hero, @scene ].each(&:delete)
      end

      # The encounters whose own record was read while the block ran.
      def loaded
        keys = []
        Thread.current[RecordsLoaded::KEY] = keys

        yield

        (@ended + [ @running ]).map { |one| one.id }.select { |id| keys.include?(PF2Encounter.key[id].to_s) }
      ensure
        Thread.current[RecordsLoaded::KEY] = nil
      end

      it "should read only the running one of a scene's" do
        found = nil
        read = loaded { found = PF2Encounter.scene_active_encounter(Scene[@scene.id]) }

        expect([ found.id, read ]).to eq [ @running.id, [ @running.id ] ]
      end

      it "should read only the running one of a character's" do
        found = nil
        read = loaded { found = PF2Encounter.active_encounters(Character[@hero.id]) }

        expect([ found.map(&:id), read ]).to eq [ [ @running.id ], [ @running.id ] ]
      end

      it "should read only the running one of a GM's" do
        found = nil
        read = loaded { found = Combatants.encounter_run_by(Character[@gm.id]) }

        expect([ found.id, read ]).to eq [ @running.id, [ @running.id ] ]
      end

      it "should find one again once it is restarted, and lose it once it ends" do
        @ended.first.update(:is_active => true)
        @running.update(:is_active => false)

        expect(PF2Encounter.scene_active_encounter(Scene[@scene.id]).id).to eq @ended.first.id
      end

      # What ran before the index was kept is put in it the first time it is asked for, and only once.
      it "should put what was already running in the index, once" do
        Ohm.redis.call('SREM', PF2Encounter.key[:indices][:is_active][true].to_s, @running.id)
        Ohm.redis.call('DEL', PF2Encounter::INDEXED)
        PF2Encounter.instance_variable_set(:@indexed, nil)

        expect(PF2Encounter.scene_active_encounter(Scene[@scene.id]).id).to eq @running.id
        expect(loaded { PF2Encounter.scene_active_encounter(Scene[@scene.id]) }).to eq [ @running.id ]
      end
    end
  end
end
