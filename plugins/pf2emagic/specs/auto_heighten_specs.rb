require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # A spell that heightens by itself reaches half its caster's level, rounded up: a 3rd-level caster
    # casts at 2nd rank, and a 19th-level one at 10th.
    describe "the rank a spell heightens to by itself" do
      { 1 => 1, 2 => 1, 3 => 2, 4 => 2, 5 => 3, 9 => 5, 10 => 5, 19 => 10, 20 => 10 }.each do |level, rank|
        it "should be #{rank} at level #{level}" do
          expect(Pf2emagic.get_auto_heighten_level(double(:pf2_level => level))).to eq rank
        end
      end
    end
  end
end
