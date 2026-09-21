require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Whether a list of traits holds one.
    #
    # The weapon catalogue writes traits Title Case with parenthesised parameters, chargen writes an
    # unarmed attack's lowercase, and a few are slugs. A reader comparing with `include?` answers no
    # for half the game's data, which is how every finesse weapon came to use Strength.
    describe :has_trait? do

      it "should find a trait written the way the catalogue writes it" do
        expect(Pf2e.has_trait?([ 'Finesse', 'Agile' ], 'finesse')).to be true
      end

      it "should find one written the way chargen writes it" do
        expect(Pf2e.has_trait?([ 'finesse' ], 'Finesse')).to be true
      end

      it "should ignore surrounding space" do
        expect(Pf2e.has_trait?([ ' Finesse ' ], 'finesse')).to be true
      end

      it "should not find one that is not there" do
        expect(Pf2e.has_trait?([ 'Agile', 'Deadly (d8)' ], 'finesse')).to be false
      end

      # A parameterised trait is one string, so asking for the bare name does not match it. That is
      # the behaviour to keep in mind when traits are slugified.
      it "should not match a parameterised trait by its bare name" do
        expect(Pf2e.has_trait?([ 'Deadly (d8)' ], 'deadly')).to be false
      end

      it "should answer no for nothing at all" do
        expect(Pf2e.has_trait?(nil, 'finesse')).to be false
      end
    end
  end
end
