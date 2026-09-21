require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What `advance/review` says about a slot the level has left open.
    #
    # It named the slot but said nothing about where the commands are, and a player who cannot find
    # them cannot finish the level. Two players lost their Multilingual languages to exactly this:
    # the slot showed as outstanding, `lang/set` is chargen-only, and nothing pointed anywhere.
    #
    # The pointer is the help topic rather than the command grammar, which is how `cg/review`
    # answers the same question: the grammar written out here would be a second copy of the
    # parsers, kept in step by hand.
    describe PF2AdvanceReviewTemplate do

      # Every alias the table points at, as the help files define them.
      TOPICS = %w{advancelanguages advanceskills advanceattributes advancefeats advancefeatures
                  advancearchetypes advancespells}.freeze

      describe :help_for do
        it "should point an open language slot at the languages topic" do
          expect(PF2AdvanceReviewTemplate.help_for('open languages')).to include 'advancelanguages'
        end

        it "should name an activity and a topic for each slot it knows" do
          missing = PF2AdvanceReviewTemplate::RESOLVED_BY.reject do |_key, (activity, topic)|
            activity.to_s.match?(/\A[a-z]/) && TOPICS.include?(topic.to_s)
          end

          expect(missing).to eq({})
        end

        # A topic that no help file answers to renders as a pointer to nothing.
        it "should point only at topics the help files define" do
          defined = Dir[File.join(AresMUSH.game_path, '..', 'plugins', 'pf2e', 'help', 'en', '*.md')]
                      .flat_map { |path| File.read(path).scan(/^- (\S+)$/).flatten }

          expect(TOPICS - defined).to eq []
        end

        it "should say nothing for a slot it has no topic for, rather than guessing" do
          expect(PF2AdvanceReviewTemplate.help_for('something nobody has heard of')).to be_nil
        end

        # The keys are the ones to_assign actually uses, so a renamed key loses its hint silently.
        it "should key its hints on slots the draft really holds" do
          known = Pf2e::DraftKeys::KEYS.keys.map(&:to_s)
          strays = PF2AdvanceReviewTemplate::RESOLVED_BY.keys.map(&:to_s) - known

          expect(strays).to eq []
        end

        # Every slot a player is left to fill themselves needs a pointer against it. These are the
        # ones a level actually leaves open, and driving a character through level 11 found four of
        # them rendering with nothing at all: the pointer was appended on one branch of the review's
        # renderer and these go through the others.
        FILLED_BY_THE_PLAYER = [
          'raise ability', 'raise skill', 'raise skill choice', 'open languages', 'open skills',
          'feats', 'feat choice', 'repertoire', 'spellbook', 'innate', 'class option',
          'divine font', 'archetype_specialty', 'archetype specialty choice', 'archetype deity',
          'archetype key ability'
        ].freeze

        it "should have a topic for every slot the player has to fill" do
          missing = FILLED_BY_THE_PLAYER.reject { |key| PF2AdvanceReviewTemplate.help_for(key) }

          expect(missing).to eq []
        end
      end
    end
  end
end
