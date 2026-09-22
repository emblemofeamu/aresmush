require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      # Applying a level's skill increases at advance/done.
      #
      # A raise with no rank above it must leave the skill as it is. Writing what get_next_prof
      # returned without checking it blanked a skill that was already legendary, and a proficiency
      # off the progression took the whole commit down - locking the level in with its skills half
      # written, which cost a player level 19 outright.
      describe :raise_skills do

        def skill(prof)
          written = []
          object = double(:name => 'Occultism', :prof_level => prof, :name_upcase => 'OCCULTISM')
          allow(object).to receive(:update) { |attrs| written << attrs }
          allow(object).to receive(:written) { written }

          object
        end

        def apply(object, names)
          char = double(:name => 'Someone')
          allow(Pf2eSkills).to receive(:find_skill).and_return(object)
          allow(Global).to receive(:logger).and_return(double(:error => nil, :debug => nil))

          Apply.raise_skills(char, names)
        end

        before(:each) do
          allow(Global).to receive(:read_config).and_call_original
          allow(Global).to receive(:read_config).with('pf2e', 'prof_progression')
            .and_return([ 'untrained', 'trained', 'expert', 'master', 'legendary' ])
        end

        it "should raise a skill by one rank" do
          object = skill('trained')
          apply(object, [ 'Occultism' ])

          expect(object.written).to eq [ { :prof_level => 'expert' } ]
        end

        it "should leave a legendary skill alone rather than blanking it" do
          object = skill('legendary')
          apply(object, [ 'Occultism' ])

          expect(object.written).to eq []
        end

        it "should not raise when a proficiency is not on the progression" do
          object = skill('heroic')

          expect { apply(object, [ 'Occultism' ]) }.to_not raise_error
          expect(object.written).to eq []
        end

        it "should finish the rest of the level when one skill cannot be raised" do
          object = skill('legendary')

          expect(apply(object, [ 'Occultism' ])).to eq []
        end

        it "should say in the log why a raise was skipped" do
          logger = double(:debug => nil)
          expect(logger).to receive(:error).with(/legendary|Occultism/)

          allow(Pf2eSkills).to receive(:find_skill).and_return(skill('legendary'))
          allow(Global).to receive(:logger).and_return(logger)

          Apply.raise_skills(double(:name => 'Someone'), [ 'Occultism' ])
        end
      end
    end
  end
end
