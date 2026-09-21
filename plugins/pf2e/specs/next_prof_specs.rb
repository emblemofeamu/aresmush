require "plugin_test_loader"

module AresMUSH

  # The next rank up for a skill, which a level-up applies at advance/done.
  #
  # It read `progression[index + 1]` with no check on `index`, so a proficiency that is not on the
  # progression at all raised NoMethodError and took the whole of advance/done with it - the level
  # was locked in with its skills half written. And a skill already at the top of the progression
  # got `progression[5]`, which is nil: the raise silently blanked a legendary skill instead of
  # leaving it alone.
  describe :get_next_prof do

    def char_with(prof)
      skill = double(:name => 'Occultism', :prof_level => prof, :name_upcase => 'OCCULTISM')
      char = double(:name => 'Someone', :skills => [ skill ])

      allow(Pf2eSkills).to receive(:find_skill).and_return(skill)

      char
    end

    before(:each) do
      allow(Global).to receive(:read_config).and_call_original
      allow(Global).to receive(:read_config).with('pf2e', 'prof_progression')
        .and_return([ 'untrained', 'trained', 'expert', 'master', 'legendary' ])
    end

    it "should step one rank up" do
      expect(Pf2eSkills.get_next_prof(char_with('trained'), 'Occultism')).to eq 'expert'
    end

    it "should step up from untrained" do
      expect(Pf2eSkills.get_next_prof(char_with('untrained'), 'Occultism')).to eq 'trained'
    end

    # Nothing is above legendary, so there is no next rank to hand back - and handing back nil as
    # if it were one is what wiped the skill.
    it "should offer nothing above the top of the progression" do
      expect(Pf2eSkills.get_next_prof(char_with('legendary'), 'Occultism')).to be_nil
    end

    it "should offer nothing for a proficiency that is not on the progression" do
      expect(Pf2eSkills.get_next_prof(char_with('heroic'), 'Occultism')).to be_nil
    end

    it "should not raise for a skill with no proficiency recorded" do
      expect { Pf2eSkills.get_next_prof(char_with(nil), 'Occultism') }.to_not raise_error
    end

    it "should not raise for a skill it cannot find" do
      allow(Pf2eSkills).to receive(:find_skill).and_return(nil)

      expect { Pf2eSkills.get_next_prof(double(:name => 'Someone'), 'Occultism') }.to_not raise_error
    end
  end
end
