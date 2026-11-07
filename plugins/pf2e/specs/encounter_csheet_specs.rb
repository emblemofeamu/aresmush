require "plugin_test_loader"
require_relative "support/fight_bench"

module AresMUSH
  module Pf2e

    # `encounter/csheet <who>`: a character's combat sheet as they stand in the encounter - their Strikes
    # with what they carry there and what they are under there. `csheet` is the character without it.
    describe "an encounter combat sheet", :dbtest => true do
      include FightBench

      before(:each) do
        bench!
        @combat.update(:weapon_prof => { 'unarmed' => 'trained', 'martial' => 'trained' })
      end

      after(:each) do
        Pf2e::ActiveEffects.on(hero).each(&:delete)
        PF2Weapon.find(:character_id => @hero.id).each(&:delete)
        clear_bench!
      end

      def shown(text = "e/csheet #{@hero.name}", who = @gm)
        @client.said.clear
        run(PF2EncounterCombatSheetCmd, text, who)

        heard
      end

      def own_sheet
        PF2CombatSheetTemplate.new(Character[@hero.id], @client).render.gsub(/%x(?:\d{1,3}|[a-zA-Z])/, '')
      end

      it "should be routed from the encounter command" do
        expect(Pf2e.get_cmd_handler(@client, Command.new('e/csheet'), Character[@hero.id])).to eq PF2EncounterCombatSheetCmd
      end

      it "should show the combatant's attacks" do
        expect(refused).to eq []
        expect(shown).to include 'Combat Sheet', 'Fist', 'Claw'
      end

      it "should show your own when you name nobody" do
        expect(shown('e/csheet', @hero)).to include "Combat Sheet: #{@hero.name}"
      end

      # They fight with what they carried in; a weapon bought since is on their own sheet only.
      it "should show what they carry in the encounter, not what they bought since" do
        sword = Pf2egear.create_item(Character[@hero.id], 'weapons', 'Longsword', 1, Global.read_config('pf2e_weapons', 'Longsword'))
        sword.update(:equipped => true)

        expect(own_sheet).to include 'Longsword'
        expect(shown).to_not include 'Longsword'
      end

      it "should show only a stance's attack while they are in it there" do
        Pf2e::ActiveEffects.apply(hero, 'Stance: Stumbling Stance', :encounter => encounter)

        sheet = shown
        expect(sheet).to include 'Stumbling Swing', t('pf2e.csheet_strikes_replaced', :source => 'Stumbling Stance',
                                                                                        :attacks => 'Stumbling Swing')
        expect(sheet).to_not include 'Fist:'
        expect(own_sheet).to include 'Fist:'
      end

      it "should show only a form's attacks while they are in it there" do
        Pf2e::ActiveEffects.apply(hero, 'Spell Effect: Animal Form (Bear)', :options => [ 'rank 5' ], :encounter => encounter)

        sheet = shown
        expect(sheet).to include 'Jaws: 18', 'Claw: 18', t('pf2e.csheet_strikes_replaced', :source => 'Animal Form (Bear)',
                                                                                           :attacks => 'Claw, Jaws')
        expect(sheet).to_not include 'Fist:'
      end

      it "should refuse a creature" do
        add('goblin warrior')

        shown('e/csheet #2')

        expect(refused).to eq [ t('pf2e.encounter_sheet_creature', :ref => '#2') ]
      end
    end
  end
end
