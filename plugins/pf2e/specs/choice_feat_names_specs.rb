require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # A feat choice whose pool is a named pair rather than a whole category.
    #
    # PF2e has several features that hand over one of two specific feats. The Druid's is
    # Voice of Nature: "You gain your choice of the Animal Empathy or Plant Empathy druid feat"
    # (Player Core, via Archives of Nethys). `from_feats` could filter a pool by type, traits or
    # level, but not down to a named list, so there was no way to express it - which is why the
    # Druid's table put the two feat names in `choose_feat`, a field that holds slot *types*,
    # where they did nothing at all. See finding 29.
    describe :choice_feat_pool do

      def feats
        {
          'Animal Empathy' => { 'feat_type' => [ 'Charclass' ], 'assoc_charclass' => [ 'Druid' ] },
          'Plant Empathy' => { 'feat_type' => [ 'Charclass' ], 'assoc_charclass' => [ 'Druid' ] },
          'Wild Shape' => { 'feat_type' => [ 'Charclass' ], 'assoc_charclass' => [ 'Druid' ] }
        }
      end

      def char
        double(:pf2_base_info => { 'charclass' => 'Druid', 'heritage' => nil },
               :pf2_feats => {}, :pf2_to_assign => {}, :name => 'Someone',
               :pf2_archetypeinfo => {}, :advancing => nil, :pf2_level => 1)
      end

      before(:each) do
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(feats)
        allow(Pf2e).to receive(:feat_repeat_block).and_return(nil)
        allow(Pf2e).to receive(:dedication_allowed?).and_return(true)
        allow(Pf2e).to receive(:feat_tally).and_return({})
      end

      it "should offer only the feats a names filter lists" do
        pool = Pf2e.choice_feat_pool(char, 'names' => [ 'Animal Empathy', 'Plant Empathy' ])

        expect(pool).to eq [ 'Animal Empathy', 'Plant Empathy' ]
      end

      it "should match a name however it was capitalised in the filter" do
        pool = Pf2e.choice_feat_pool(char, 'names' => [ 'animal empathy' ])

        expect(pool).to eq [ 'Animal Empathy' ]
      end

      it "should offer nothing for a name the game does not define" do
        expect(Pf2e.choice_feat_pool(char, 'names' => [ 'Nonexistent Feat' ])).to eq []
      end

      it "should still filter by type when no names are given" do
        pool = Pf2e.choice_feat_pool(char, 'feat_type' => [ 'charclass' ])

        expect(pool).to eq [ 'Animal Empathy', 'Plant Empathy', 'Wild Shape' ]
      end

      # A names filter is a whitelist, so a feat on the list that fails another clause of the
      # same filter is still out.
      it "should combine a names filter with the rest of the filter" do
        pool = Pf2e.choice_feat_pool(char, 'names' => [ 'Animal Empathy' ], 'feat_type' => [ 'skill' ])

        expect(pool).to eq []
      end
    end
  end
end
