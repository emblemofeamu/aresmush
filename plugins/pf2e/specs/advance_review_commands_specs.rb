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
      end
    end
  end
end
