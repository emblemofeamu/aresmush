require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # Seek, Hide and Sneak against the one they are aimed at, and what they leave of who can be seen;
    # Recall Knowledge against what a creature's level and rarity make it.
    describe "seeking, hiding and knowing", :dbtest => true do
      include FightBench

      before(:each) { bench! }
      after(:each) { clear_bench! }

      def unseen(number)
        (encounter.concealment || {})[number.to_s]
      end

      def hero_number
        Combatants.find(encounter, @hero.name).state.number
      end

      # A lurker whose Stealth DC the hero's Perception makes exactly on a 12.
      describe "Seek" do
        before(:each) do
          add("Lurker=ac 10 hp 50; skills stealth #{Stat.total(hero, 'perception') + 2}")
        end

        it "should be against the Stealth DC of whoever it is aimed at" do
          hero_types('e/act seek=#2')

          expect(heard).to include("vs Stealth DC #{Stat.total(hero, 'perception') + 12}")
        end

        it "should leave what was undetected hidden on a success" do
          run(PF2EncounterConcealCmd, 'e/conceal #2=undetected')
          hero_types('e/act seek=#2')

          expect(unseen(2)).to eq 'hidden'
          expect(heard).to include(t('pf2e.act_concealment_now', :target => 'Lurker #2', :level => 'hidden').strip)
        end

        it "should leave what was hidden seen on a success" do
          run(PF2EncounterConcealCmd, 'e/conceal #2=hidden')
          hero_types('e/act seek=#2')

          expect(unseen(2)).to be_nil
          expect(heard).to include(t('pf2e.act_concealment_none', :target => 'Lurker #2').strip)
        end

        it "should leave what was undetected seen on a critical success" do
          run(PF2EncounterConcealCmd, 'e/conceal #2=undetected')
          hero_types('e/act seek=#2', 1.0)

          expect(unseen(2)).to be_nil
        end

        it "should change nothing on a failure" do
          run(PF2EncounterConcealCmd, 'e/conceal #2=hidden')
          hero_types('e/act seek=#2', FightBench::LOW)

          expect(unseen(2)).to eq 'hidden'
        end

        it "should not see through what only conceals" do
          run(PF2EncounterConcealCmd, 'e/conceal #2=concealed')
          hero_types('e/act seek=#2')

          expect(unseen(2)).to eq 'concealed'
        end

        it "should be a roll for the GM to read where it is aimed at nobody" do
          hero_types('e/act seek')

          expect(refused).to eq []
          expect(heard).to_not include('DC')
        end
      end

      # A watcher whose Perception DC is 10.
      describe "Hide and Sneak" do
        before(:each) { add('Watcher=ac 10 hp 50 perception 0') }

        it "should leave whoever hides hidden on a success" do
          hero_types('e/act hide=#2', FightBench::HIGH)

          expect(heard).to include('vs Perception DC 10')
          expect(unseen(hero_number)).to eq 'hidden'
        end

        it "should leave them seen where the Hide fails" do
          hero_types('e/act hide=#2', FightBench::LOW)

          expect(unseen(hero_number)).to be_nil
        end

        it "should leave whoever sneaks undetected on a success" do
          hero_types('e/act sneak=#2', FightBench::HIGH)

          expect(unseen(hero_number)).to eq 'undetected'
        end

        it "should leave them hidden where the Sneak fails, and seen where it fails badly" do
          add("Sentinel=ac 10 hp 50 perception #{Stat.total(hero, 'skill', 'Stealth') + 5}")
          hero_types('e/act sneak=#3', 0.6)

          expect(unseen(hero_number)).to eq 'hidden'

          hero_types('e/act sneak=#3', FightBench::LOW)

          expect(unseen(hero_number)).to be_nil
        end

        it "should keep someone undetected who Hides" do
          hero_types('e/act sneak=#2', FightBench::HIGH)
          hero_types('e/act hide=#2', FightBench::HIGH)

          expect(unseen(hero_number)).to eq 'undetected'
        end

        it "should leave someone undetected only hidden where their Sneak fails" do
          add("Sentinel=ac 10 hp 50 perception #{Stat.total(hero, 'skill', 'Stealth') + 5}")
          run(PF2EncounterConcealCmd, "e/conceal ##{hero_number}=undetected")
          hero_types('e/act sneak=#3', 0.6)

          expect(unseen(hero_number)).to eq 'hidden'
        end
      end

      # One check against each creature named. A 12 on the die beats the Watcher's DC of 10 and falls 3 short
      # of the Sentinel's; a 19 beats both.
      describe "aimed at several" do
        before(:each) do
          add('Watcher=ac 10 hp 50 perception 0')
          add("Sentinel=ac 10 hp 50 perception #{Stat.total(hero, 'skill', 'Stealth') + 5}")
        end

        it "should tell a result against each creature" do
          hero_types('e/act sneak=#2,#3', 0.6)

          expect(refused).to eq []
          expect(heard).to match(/on Watcher #2: .* vs Perception DC 10/)
          expect(heard).to match(/on Sentinel #3: .* vs Perception DC/)
        end

        it "should roll one die for all of them" do
          rolls = 0
          allow(Pf2e).to receive(:roll_dice) do
            rolls += 1
            [ 12 ]
          end

          hero_types('e/act sneak=#2,#3')

          expect(rolls).to eq 1
        end

        it "should cost one action" do
          hero_types('e/act sneak=#2,#3', 0.6)

          expect(TurnState.turn(hero)['actions']).to eq 1
        end

        it "should leave a Sneak at its worst result" do
          hero_types('e/act sneak=#2,#3', 0.6)

          expect(unseen(hero_number)).to eq 'hidden'
          expect(heard).to_not include('undetected')
        end

        it "should leave a Sneak undetected where it beats them all" do
          hero_types('e/act sneak=#2,#3', FightBench::HIGH)

          expect(unseen(hero_number)).to eq 'undetected'
        end

        it "should leave whoever is spotted by one of them observed" do
          run(PF2EncounterConcealCmd, "e/conceal ##{hero_number}=undetected")
          hero_types('e/act sneak=#3,#2', FightBench::LOW)

          expect(unseen(hero_number)).to be_nil
        end

        it "should hide someone only where the Hide beats them all" do
          hero_types('e/act hide=#2,#3', 0.6)
          expect(unseen(hero_number)).to be_nil

          hero_types('e/act hide=#2,#3', FightBench::HIGH)
          expect(unseen(hero_number)).to eq 'hidden'
        end

        it "should find each creature by its own result" do
          perception = Stat.total(hero, 'perception')
          add("Lurker=ac 10 hp 50; skills stealth #{perception + 2}")
          add("Skulker=ac 10 hp 50; skills stealth #{perception + 5}")
          run(PF2EncounterConcealCmd, 'e/conceal #4=hidden')
          run(PF2EncounterConcealCmd, 'e/conceal #5=hidden')

          hero_types('e/act seek=#4,#5')

          expect(unseen(4)).to be_nil
          expect(unseen(5)).to eq 'hidden'
        end

        it "should find a creature named twice only once" do
          perception = Stat.total(hero, 'perception')
          add("Lurker=ac 10 hp 50; skills stealth #{perception + 2}")
          run(PF2EncounterConcealCmd, 'e/conceal #4=undetected')

          hero_types('e/act seek=#4,#4')

          expect(unseen(4)).to eq 'hidden'
        end

        it "should Create a Diversion with one roll against each creature" do
          rolls = 0
          allow(Pf2e).to receive(:roll_dice) do
            rolls += 1
            [ 12 ]
          end

          hero_types('e/act create a diversion=#2,#3/manipulate')

          expect(refused).to eq []
          expect(rolls).to eq 1
          expect(heard).to match(/on Watcher #2: Deception .* vs Perception DC 10/)
          expect(heard).to match(/on Sentinel #3: Deception .* vs Perception DC/)
          expect(TurnState.turn(hero)['actions']).to eq 1
        end

        it "should tell what a Diversion's result means once, however many it beat" do
          hero_types('e/act create a diversion=#2,#3/manipulate', FightBench::HIGH)

          expect(heard.scan('You become Hidden to each creature').size).to eq 1
        end

        # What a Diversion's result does is told, and left to the GM.
        it "should leave it to the GM whether a Diversion hides them" do
          hero_types('e/act create a diversion=#2,#3/manipulate', FightBench::HIGH)

          expect(unseen(hero_number)).to be_nil
        end
      end

      # The traits a Diversion gains are the ones its user names, for how they do it.
      describe "the traits of a Diversion" do
        before(:each) { add('Watcher=ac 10 hp 50 perception 0') }

        def condition(name)
          run(PF2ConditionSetCmd, "condition/set #{@hero.name}=#{name}")
          @client.said.clear
        end

        it "should be refused with none named, and spend nothing" do
          hero_types('e/act create a diversion=#2', FightBench::HIGH)

          expect(refused.join).to include(t('pf2e.act_traits_needed', :action => 'Create a Diversion',
                                                                      :traits => 'auditory, linguistic, or manipulate'))
          expect(TurnState.turn(hero)['actions'].to_i).to eq 0
        end

        it "should be refused where the only word is no trait it can gain" do
          hero_types('e/act create a diversion=#2/attack', FightBench::HIGH)

          expect(refused).to_not eq []
        end

        it "should tell the room the traits named" do
          hero_types('e/act create a diversion=#2/auditory linguistic manipulate', FightBench::HIGH)

          expect(refused).to eq []
          expect(heard).to include(t('pf2e.act_traits_gained', :action => 'Create a Diversion',
                                                               :traits => 'auditory, linguistic, manipulate').gsub(/%x./, '').strip)
        end

        it "should take traits named each after a slash" do
          hero_types('e/act create a diversion=#2/auditory/manipulate', FightBench::HIGH)

          expect(refused).to eq []
          expect(heard).to include('auditory, manipulate')
        end

        it "should give no trait for a word it cannot gain" do
          hero_types('e/act create a diversion=#2/attack manipulate', FightBench::HIGH)

          expect(heard).to include('manipulate')
          expect(heard).to_not include('attack, manipulate')
        end

        it "should risk the flat check of being grabbed only for manipulate" do
          condition('Grabbed')

          hero_types('e/act create a diversion=#2/auditory', FightBench::LOW)
          expect(heard).to include('vs Perception DC 10')

          hero_types('e/act create a diversion=#2/manipulate', FightBench::LOW)
          expect(heard).to_not include('vs Perception DC 10')
          expect(heard).to include('The action is lost')
        end

        it "should risk the flat check of being deafened only for auditory" do
          condition('Deafened')

          hero_types('e/act create a diversion=#2/manipulate', FightBench::LOW)
          expect(heard).to include('vs Perception DC 10')

          hero_types('e/act create a diversion=#2/auditory', FightBench::LOW)
          expect(heard).to_not include('vs Perception DC 10')
          expect(heard).to include('The action is lost')
        end

        it "should be refused to someone restrained who names manipulate" do
          condition('Restrained')

          hero_types('e/act create a diversion=#2/manipulate', FightBench::HIGH)
          expect(refused).to_not eq []

          hero_types('e/act create a diversion=#2/auditory', FightBench::HIGH)
          expect(refused).to eq []
        end

        it "should spare a creature immune to a trait named" do
          add('Deaf One=ac 10 hp 50 perception 0; immune auditory')

          hero_types('e/act create a diversion=#2,#3/auditory', FightBench::HIGH)

          expect(heard).to include(t('pf2e.act_immune', :target => 'Deaf One #3', :to => 'auditory').strip)
          expect(heard).to include('on Watcher #2')
          expect(heard).to_not include('on Deaf One #3:')
        end
      end

      describe "Recall Knowledge" do
        # An ogre warrior is a common giant and humanoid of level 3.
        it "should be against the DC of a creature's level" do
          add('ogre warrior')
          hero_types('e/act recall knowledge=#2')

          expect(heard).to include('vs DC 18')
        end

        it "should be with the skill that knows its kind" do
          add('ogre warrior')
          hero_types('e/act recall knowledge=#2')

          expect(heard).to include('Society')
        end

        it "should be with the skill named, where that knows its kind too" do
          add('zombie shambler')
          hero_types('e/act recall knowledge=#2/religion')

          expect(heard).to include('Religion', 'vs DC 13')
        end

        # A grioth cultist is rare, and of level 3.
        it "should be 5 harder for a rare creature" do
          add('grioth cultist')
          hero_types('e/act recall knowledge=#2')

          expect(heard).to include('vs DC 23')
        end

        it "should tell the GM what the roll earned" do
          add('ogre warrior')
          hero_types('e/act recall knowledge=#2', FightBench::HIGH)

          expect(heard).to include('The GM answers your question truthfully')
        end

        it "should be a roll for the GM to read where it is about no creature" do
          hero_types('e/act recall knowledge/arcana')

          expect(refused).to eq []
          expect(heard).to include('Arcana')
          expect(heard).to_not include('DC')
        end
      end

      describe Knowledge do
        it "should give the DC of each level" do
          expect([ -1, 0, 1, 5, 10, 20, 25 ].map { |level| Knowledge.level_dc(level) }).to eq [ 13, 14, 15, 20, 27, 40, 50 ]
        end

        it "should make it harder by rarity" do
          expect(%w{common uncommon rare unique}.map { |rarity| Knowledge.dc(3, rarity) }).to eq [ 18, 20, 23, 28 ]
        end

        it "should know which skills know which kinds of creature" do
          expect(Knowledge.skills(%w{undead zombie})).to eq %w{Religion}
          expect(Knowledge.skills(%w{beast})).to eq %w{Arcana Nature}
          expect(Knowledge.skills(%w{construct mindless})).to eq %w{Arcana Crafting}
        end

        it "should leave to Society what has no kind of its own" do
          expect(Knowledge.skills(%w{nothing-known})).to eq %w{Society}
        end
      end
    end
  end
end
