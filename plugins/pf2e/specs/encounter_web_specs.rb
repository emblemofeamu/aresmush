require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # What the portal is given of an encounter.
    describe EncounterWeb, :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        add('giant rat')
        @stranger = Character.create(:name => "Odd#{rand(1000000)}")
      end

      after(:each) do
        @stranger.delete
        clear_bench!
      end

      def shown(viewer, gm)
        Combatants.all(encounter).map { |one| EncounterWeb.combatant(encounter, one, viewer, gm) }
      end

      def of(rows, name)
        rows.find { |row| row[:name].start_with?(name) }
      end

      it "should give the game's text plain, with its own line breaks and none after it" do
        expect(EncounterWeb.plain('%xhAC 18%xn')).to eq 'AC 18'
        expect(EncounterWeb.plain('one%rtwo')).to eq "one\ntwo"
      end

      describe "the way to its page" do
        it "should be given by +e/view" do
          run(PF2InitViewCmd, "e/view #{encounter.id}", @hero)

          expect(heard).to include(PF2Encounter.page_url(encounter))
        end

        it "should be found from the scene it is running in, by anyone who may read the scene" do
          allow(Website).to receive(:check_login).and_return(nil)
          asked = ->(who) { PF2SceneEncounterHandler.new.handle(double(:args => { 'scene_id' => encounter.scene.id }, :enactor => Character[who.id])) }

          expect(asked.call(@hero)).to eq(id: encounter.id, exploring: false)

          allow(Scenes).to receive(:can_read_scene?).and_return(false)
          expect(asked.call(@stranger)).to eq({})
        end
      end

      describe "the difficulty" do
        def page(viewer)
          allow(Website).to receive(:check_login).and_return(nil)
          PF2EncounterHandler.new.handle(double(:args => { 'id' => encounter.id }, :enactor => Character[viewer.id]))
        end

        it "should be sent to the GM's page only" do
          expect(page(@gm)[:difficulty]).to eq EncounterWeb.plain(Difficulty.shown(encounter)).strip
          expect(page(@hero)).to_not have_key(:difficulty)
        end

        it "should be shown by +e/view to the GM only" do
          line = EncounterWeb.plain(Difficulty.shown(encounter)).strip

          run(PF2InitViewCmd, "e/view #{encounter.id}", @gm)
          expect(heard).to include(line)

          @client.said.clear
          run(PF2InitViewCmd, "e/view #{encounter.id}", @hero)
          expect(heard).to_not include(line)
        end
      end

      describe "Hero Points" do
        it "should be shown to the GM for each character, and for no creature" do
          rows = shown(Character[@gm.id], true)

          expect(of(rows, @hero.name)[:hero_points]).to eq 1
          expect(of(rows, 'Giant Rat')[:hero_points]).to be_nil
        end

        it "should be shown to the character whose they are" do
          expect(of(shown(Character[@hero.id], false), @hero.name)[:hero_points]).to eq 1
        end

        it "should be shown to nobody who may not see that character's combat sheet" do
          allow(Sheet).to receive(:viewable?).and_return(Err.new(:not_yours, 'pf2e.not_found'))

          expect(of(shown(Character[@stranger.id], false), @hero.name)[:hero_points]).to be_nil
        end

        it "should say in the history who spent one in a change" do
          History.append(encounter, "#{@hero.name}: e/strike #2=fist", { 'encounter' => { 'round' => 1 } }, { 'encounter' => { 'round' => 2 } })
          History.latest(encounter).update(:hero_spent => { @hero.name => 1 })

          expect(EncounterWeb.history(encounter).last).to include(:heroes => [ @hero.name ])
        end
      end
    end
  end
end
