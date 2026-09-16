require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Which of a caster's slots at one rank are restricted, and to what.
    #
    # Each kind of restriction is a row: how many slots it grants at a rank, and which spells may
    # go in them. Adding a kind is adding a row, which is the point - the old shape had one
    # hardcoded `case` for 'curriculum' that logged an error for anything else, and the divine
    # font was not a restriction at all, so a Cleric's font slot did not exist.
    describe Restrictions do

      def stats(restricted = {})
        double(:restricted_slots => { 'Wizard' => restricted, 'Cleric' => {} },
               :spells_per_day => { 'Wizard' => { 'cantrip' => 5, '1' => 3, '2' => 2 },
                                    'Cleric' => { 'cantrip' => 5, '1' => 2 } },
               :divine_font => nil)
      end

      def char_for(magic, specialize = 'Battle Magic')
        double(:magic => magic,
               :pf2_base_info => { 'specialize' => specialize },
               :name => 'Someone')
      end

      describe "a curriculum" do
        before(:each) do
          allow(Pf2emagic).to receive(:curriculum_spells).and_return([ 'Fireball' ])
        end

        it "should grant the slots the stat block says" do
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.at(char, 'Wizard', '2')['curriculum']['count']).to eq 1
        end

        it "should grant nothing at a rank the stat block does not mention" do
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.at(char, 'Wizard', '1')).to eq({})
        end

        it "should take its eligible spells from the curriculum" do
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.at(char, 'Wizard', '2')['curriculum']['eligible']).to eq [ 'Fireball' ]
        end
      end

      # PF2e: "you can cast one additional spell each day at each spell rank you can cast", and it
      # must be your font spell. Tenebrae recorded the choice and printed it on the sheet, but
      # never granted the slot, so every Cleric was short one slot at every rank.
      describe "a divine font" do
        def cleric(font = 'heal')
          magic = double(:restricted_slots => { 'Cleric' => {} },
                         :spells_per_day => { 'Cleric' => { 'cantrip' => 5, '1' => 2 } },
                         :divine_font => font)

          char_for(magic, nil)
        end

        it "should grant one slot at a rank the cleric has slots at" do
          expect(Restrictions.at(cleric, 'Cleric', '1')['divine font']['count']).to eq 1
        end

        it "should only take the font's own spell" do
          expect(Restrictions.at(cleric, 'Cleric', '1')['divine font']['eligible']).to eq [ 'Heal' ]
          expect(Restrictions.at(cleric('harm'), 'Cleric', '1')['divine font']['eligible']).to eq [ 'Harm' ]
        end

        it "should grant no cantrip slot" do
          expect(Restrictions.at(cleric, 'Cleric', 'cantrip')).to eq({})
        end

        it "should grant nothing at a rank with no slots" do
          expect(Restrictions.at(cleric, 'Cleric', '4')).to eq({})
        end

        it "should grant nothing with no font chosen" do
          expect(Restrictions.at(cleric(nil), 'Cleric', '1')).to eq({})
        end

        it "should grant nothing to a class that has no font" do
          char = char_for(stats)

          expect(Restrictions.at(char, 'Wizard', '1')).to eq({})
        end
      end

      describe :counts_at do
        it "should give just the counts, for callers that only size the pools" do
          allow(Pf2emagic).to receive(:curriculum_spells).and_return([ 'Fireball' ])
          char = char_for(stats('curriculum' => { '2' => 1 }))

          expect(Restrictions.counts_at(char, 'Wizard', '2')).to eq('curriculum' => 1)
        end
      end

      describe "an unknown restriction" do
        it "should grant its slots but restrict them to nothing, rather than to anything" do
          char = char_for(stats('moon phase' => { '1' => 1 }))

          restriction = Restrictions.at(char, 'Wizard', '1')['moon phase']

          expect(restriction['count']).to eq 1
          expect(restriction['eligible']).to eq []
        end
      end
    end
  end
end
