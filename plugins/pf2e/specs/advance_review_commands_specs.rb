require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What `advance/review` says about a slot the level has left open.
    #
    # It named the slot but never the command that fills it, and a player who cannot find that
    # command cannot finish the level. Two players lost their Multilingual languages to exactly
    # this: the slot showed as outstanding, `lang/set` is chargen-only, and nothing pointed at
    # `advance/language`.
    describe PF2AdvanceReviewTemplate do

      describe :command_for do
        it "should name the command that fills an open language slot" do
          expect(PF2AdvanceReviewTemplate.command_for('open languages')).to include 'advance/language'
        end

        it "should name the command for each slot it knows" do
          missing = PF2AdvanceReviewTemplate::RESOLVED_BY.reject { |_key, hint| hint.to_s.include?('advance/') }

          expect(missing).to eq({})
        end

        it "should say nothing for a slot it has no command for, rather than guessing" do
          expect(PF2AdvanceReviewTemplate.command_for('something nobody has heard of')).to be_nil
        end

        # The keys are the ones to_assign actually uses, so a renamed key loses its hint silently.
        it "should key its hints on slots the draft really holds" do
          known = Pf2e::DraftKeys::KEYS.keys.map(&:to_s)
          strays = PF2AdvanceReviewTemplate::RESOLVED_BY.keys.map(&:to_s) - known

          expect(strays).to eq []
        end

        # Every slot a player is left to fill themselves needs a command against it. These are the
        # ones a level actually leaves open, and driving a character through level 11 found four of
        # them rendering with no hint at all: the hint was appended on one branch of the review's
        # renderer and these go through the others.
        FILLED_BY_THE_PLAYER = [
          'raise ability', 'raise skill', 'raise skill choice', 'open languages', 'open skills',
          'feats', 'feat choice', 'repertoire', 'spellbook', 'innate', 'class option',
          'divine font', 'archetype_specialty', 'archetype specialty choice', 'archetype deity',
          'archetype key ability'
        ].freeze

        it "should have a command for every slot the player has to fill" do
          missing = FILLED_BY_THE_PLAYER.reject { |key| PF2AdvanceReviewTemplate.command_for(key) }

          expect(missing).to eq []
        end
      end
    end
  end
end
