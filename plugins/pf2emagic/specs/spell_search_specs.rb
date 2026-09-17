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
        { 'Force Barrage' => {}, 'Frostbite' => {}, 'Breathe Fire' => {}, 'Charm' => {} }
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
    end
  end
end
