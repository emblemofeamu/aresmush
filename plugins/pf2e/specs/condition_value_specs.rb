require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a condition is worth to arithmetic.
    #
    # `get_condition_value` tells absent (nil) from present-without-a-value (0), which a display
    # needs. Everything that does sums with it wants a number, and the dying rules add and subtract
    # three conditions at once - so `1 + nil` was one absent condition away in the path that decides
    # whether a character is dying or dead.
    describe :condition_level do

      # Nothing alters a condition's value here: that is `Alterations`' own to answer, and this is about
      # the arithmetic. Nor is anyone carrying too much.
      before(:each) do
        allow(Pf2e::Alterations).to receive(:condition) { |_char, _name, value| value }
        allow(Pf2egear::Bulk).to receive(:encumbered?).and_return(false)
      end

      # A character under no effects, since what an effect brings with it is a condition too.
      def char(conditions)
        double(:name => 'Someone', :pf2_conditions => conditions, :pf2_effects => [])
      end

      it "should be the value a condition carries" do
        expect(Pf2e.condition_level(char('Wounded' => { 'value' => 2 }), 'Wounded')).to eq 2
      end

      it "should be zero for a condition the character does not have" do
        expect(Pf2e.condition_level(char({}), 'Wounded')).to eq 0
      end

      it "should be zero for a condition held without a value" do
        expect(Pf2e.condition_level(char('Blinded' => { 'status' => true }), 'Blinded')).to eq 0
      end

      it "should be zero rather than nil, so it can be added to" do
        expect(Pf2e.condition_level(char({}), 'Doomed') + 1).to eq 1
      end

      it "should match the name however it was capitalised" do
        expect(Pf2e.condition_level(char('Wounded' => { 'value' => 3 }), 'wounded')).to eq 3
      end

      it "should answer for a character carrying no conditions at all" do
        expect(Pf2e.condition_level(double(:name => 'Someone', :pf2_conditions => nil, :pf2_effects => []), 'Wounded')).to eq 0
      end

      # The distinction the display relies on has to survive.
      it "should still let get_condition_value tell absent from valueless" do
        expect(Pf2e.get_condition_value(char({}), 'Blinded')).to be_nil
        expect(Pf2e.get_condition_value(char('Blinded' => { 'status' => true }), 'Blinded')).to eq 0
      end
    end
  end
end
