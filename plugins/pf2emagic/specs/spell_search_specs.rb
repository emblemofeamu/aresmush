require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # The command the magic help sends a player to when they do not know a spell's name.
    #
    # A term with no `=` reached nil.split and took the command down, so `spell/search arcane`
    # answered "undefined method `split' for nil" - and a caster with no way to find a spell name
    # cannot finish a level-up.
    describe PF2SearchSpellCmd do

      def parsed(args)
        cmd = double(:args => args)
        handler = PF2SearchSpellCmd.new(double, cmd, double)
        handler.parse_args
        handler
      end

      it "should split an attribute from its term" do
        expect(parsed('tradition=arcane').search).to eq [ [ 'tradition', 'arcane' ] ]
      end

      it "should take several pairs" do
        expect(parsed('tradition=arcane, level=1').search)
          .to eq [ [ 'tradition', 'arcane' ], [ 'level', '1' ] ]
      end

      it "should refuse a term with no attribute rather than raising" do
        expect(parsed('arcane').check_search_term).to_not be_nil
      end

      it "should refuse a pair whose term is blank" do
        expect(parsed('tradition=').check_search_term).to_not be_nil
      end

      it "should accept an operator in front of the term" do
        expect(parsed('level=> 3').check_search_term).to be_nil
      end

      # An operator is only meaningful on a numeric search. Everywhere else the whole term is the
      # term, and a spell whose name runs to three words is not a syntax error.
      it "should accept a name of any length" do
        expect(parsed('name=Wall of Fire').check_search_term).to be_nil
      end

      it "should keep a two-word name whole rather than reading the first word as an operator" do
        expect(parsed('name=Magic Missile').term_and_operator('name', 'Magic Missile')).to eq [ 'Magic Missile', nil ]
      end

      it "should still read an operator off a level search" do
        expect(parsed('level=> 3').term_and_operator('level', '> 3')).to eq [ '3', '>' ]
      end

      # A spell whose name holds an equals sign is not a thing, but a term that does should not
      # silently become three fields.
      it "should keep everything after the first equals as the term" do
        expect(parsed('name=a=b').search).to eq [ [ 'name', 'a=b' ] ]
      end
    end
  end
end

module AresMUSH
  module Pf2emagic

    # A name that matched nothing.
    #
    # The shipped data uses Remaster names; a player arrives with the pre-Remaster ones and gets
    # told only that the spell is not in the database. Every caster in a twenty-player test lost
    # time to this.
    describe :no_such_spell_message do

      def catalogue
        { 'Force Barrage' => {}, 'Frostbite' => {}, 'Breathe Fire' => {}, 'Charm' => {}, 'Detect Magic' => {} }
      end

      it "should offer a spell sharing a word with what they typed" do
        message = Pf2emagic.no_such_spell_message('Fire Shield', catalogue)

        expect(message).to include 'Breathe Fire'
      end

      it "should offer nothing when nothing is close" do
        message = Pf2emagic.no_such_spell_message('Wish', catalogue)

        expect(message).to_not include 'Breathe Fire'
      end

      # Short words match everything, so they are not worth offering on.
      it "should ignore a two-letter word" do
        expect(Pf2emagic.no_such_spell_message('of', catalogue)).to_not include 'Charm'
      end

      # A wholesale rename is beyond any string match, so the rename table answers those.
      describe "a pre-Remaster name" do
        before(:each) do
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e_renames', 'spells')
            .and_return({ 'Magic Missile' => { 'status' => 'renamed', 'to' => 'Force Barrage' } })
        end

        it "should name the spell it became" do
          expect(Pf2emagic.no_such_spell_message('Magic Missile', catalogue)).to include 'Force Barrage'
        end

        it "should not pad a known rename with guesses at what else they might have meant" do
          expect(Pf2emagic.no_such_spell_message('Magic Missile', catalogue)).to_not include 'Did you mean'
        end

        it "should still guess when the table only has names near the one they typed" do
          message = Pf2emagic.no_such_spell_message('Magic', catalogue)

          expect(message).to include 'Magic Missile'
          expect(message).to include 'Force Barrage'
        end
      end
    end
  end
end
