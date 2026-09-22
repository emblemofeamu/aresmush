require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Which word a player has to reach for.
    #
    # Everything a level offers is a switch of one command - `advance/feat`, `advance/raise`,
    # `advance/language`, `advance/option` - so a player who has found `advance/review` can find the
    # rest. Chargen grew the other way: `cg/review`, `cg/feat` and `cg/option`, but `boost/set`,
    # `skill/set`, `lang/set`, `dfont` and `commit`, each its own root, and `cg/review` names none of
    # them.
    #
    # Each of those answers to `cg` as well, as a shortcut - the same mechanism `csheet` and `tinit`
    # already use - so the older spellings keep working, which matters because they are in every help
    # file the players have read.
    describe "the chargen and advancement command surface" do

      def shortcuts
        Global.read_config('pf2e', 'shortcuts') || {}
      end

      # What the dispatcher would run for what a player typed, after the shortcuts have had it.
      def handler_for(text)
        command = Command.new(text)
        CommandAliasParser.substitute_aliases(nil, command, shortcuts)

        Pf2e.get_cmd_handler(double, command, double) ||
          Pf2emagic.get_cmd_handler(double, command, double)
      end

      def resolved(text)
        command = Command.new(text)
        CommandAliasParser.substitute_aliases(nil, command, shortcuts)

        [ command.root, command.switch, command.args ]
      end

      # The pick, the command it has always had, and the spelling it now also answers to.
      SAME_COMMAND = [
        [ 'an ability boost', 'boost/set free=Strength', 'cg/boost free=Strength' ],
        [ 'taking a boost back', 'boost/unset free=Strength', 'cg/unboost free=Strength' ],
        [ 'a skill', 'skill/set free=Athletics', 'cg/skill free=Athletics' ],
        [ 'taking a skill back', 'skill/unset free=Athletics', 'cg/unskill free=Athletics' ],
        [ 'a language', 'lang/set Kamin', 'cg/language Kamin' ],
        [ 'taking a language back', 'lang/unset Kamin', 'cg/unlanguage Kamin' ],
        [ 'the divine font', 'dfont heal', 'cg/font heal' ],
        [ 'committing a stage', 'commit skills', 'cg/commit skills' ]
      ].freeze

      SAME_COMMAND.each do |what, original, under_cg|
        describe what do
          it "should run the same command either way" do
            expect(handler_for(under_cg)).to eq handler_for(original)
            expect(handler_for(under_cg)).to_not be_nil
          end

          it "should keep what the player typed after the command" do
            expect(resolved(under_cg)).to eq resolved(original)
          end
        end
      end

      it "should answer a divine font owed by a level under advance, as advance/review says" do
        expect(handler_for('advance/font heal')).to eq handler_for('dfont heal')
        expect(resolved('advance/font heal').last).to eq 'heal'
      end

      it "should take the short spelling of a language too" do
        expect(resolved('cg/lang Kamin')).to eq resolved('lang/set Kamin')
        expect(resolved('cg/unlang Kamin')).to eq resolved('lang/unset Kamin')
      end

      # Every pick a player makes at a level is a switch of `advance`. Nothing here is new; the row
      # is what keeps the next one from arriving under a root of its own.
      ADVANCEMENT_PICKS = %w{feat raise language spell swapspell option archetype font}.freeze

      it "should keep every advancement pick under one command" do
        missing = ADVANCEMENT_PICKS.reject { |switch| handler_for("advance/#{switch} x") }

        expect(missing).to eq []
      end

      # A shortcut whose target nothing dispatches answers with nothing at all: `formulalist` pointed
      # at `formulas/list`, which is not a switch the plugin has. A target that is a bare root - the
      # `boog` that stands in for `boost` - carries the player's own switch, so it is not one of
      # these.
      it "should point every shortcut at a command that exists" do
        full = shortcuts.select { |_typed, real| real.to_s.include?('/') }
        strays = full.reject { |_typed, real| handler_for("#{real} x") }

        expect(strays.keys).to eq []
      end
    end
  end
end
