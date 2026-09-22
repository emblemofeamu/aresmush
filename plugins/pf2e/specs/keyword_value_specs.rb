require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Resolving a word in a roll string to a number.
    #
    # `roll` takes arbitrary words - a save, a skill, an ability, a shorthand - and every one of
    # them has to come back as something that can be added up.
    describe :get_keyword_value do

      def char
        strength = double(:shortname => 'STR', :name => 'Strength', :name_upcase => 'STRENGTH')

        double(:abilities => [ strength ], :pf2_level => 5, :is_admin? => false, :name => 'Someone')
      end

      # `char.abilities.select { }` returns an array, so a lookup needs `.first` - an array is
      # truthy, so a `return 0 if !obj` guard does not catch the miss and `obj.name` raises.
      it "should resolve an abbreviated ability" do
        allow(Pf2eAbilities).to receive(:get_score).with(anything, 'Strength').and_return(18)
        allow(Pf2eAbilities).to receive(:abilmod).with(18).and_return(4)

        expect(Pf2e.get_keyword_value(char, 'str')).to eq 4
      end

      it "should resolve an abbreviated ability whatever case it was typed in" do
        allow(Pf2eAbilities).to receive(:get_score).with(anything, 'Strength').and_return(18)
        allow(Pf2eAbilities).to receive(:abilmod).with(18).and_return(4)

        expect(Pf2e.get_keyword_value(char, 'STR')).to eq 4
      end

      it "should give nothing for an ability the character has no score for" do
        expect(Pf2e.get_keyword_value(char, 'dex')).to eq 0
      end

      it "should resolve a full ability name" do
        allow(Pf2eAbilities).to receive(:get_score).and_return(14)
        allow(Pf2eAbilities).to receive(:abilmod).with(14).and_return(2)

        expect(Pf2e.get_keyword_value(char, 'strength')).to eq 2
      end

      it "should resolve a save" do
        allow(Pf2eCombat).to receive(:get_save_bonus).with(anything, 'will').and_return(11)

        expect(Pf2e.get_keyword_value(char, 'Will')).to eq 11
      end

      it "should resolve perception" do
        allow(Pf2eCombat).to receive(:get_perception).and_return(9)

        expect(Pf2e.get_keyword_value(char, 'perception')).to eq 9
      end

      it "should give nothing for an attack keyword, which only picks the linked ability" do
        expect(Pf2e.get_keyword_value(char, 'melee')).to eq 0
      end

      it "should give nothing for a word it does not know" do
        allow(Global).to receive(:read_config).with('pf2e_skills').and_return({})

        expect(Pf2e.get_keyword_value(char, 'banana')).to eq 0
      end
    end
  end
end
