require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Which feat slots a level still has open.
    #
    # `advance/info <type>` already lists the feats eligible for one slot type, but a player has to
    # know the vocabulary - general, skill, ancestry, charclass, archetype - to ask. This is what
    # lets one command answer "what can I take right now" without being told the words first.
    describe :open_feat_slot_types do

      def char(feats)
        double(:pf2_to_assign => { 'feats' => feats }, :name => 'Someone')
      end

      it "should name a slot type with an open slot in it" do
        expect(Pf2e.open_feat_slot_types(char('skill' => [ 'open' ]))).to eq [ 'skill' ]
      end

      it "should leave out a slot type whose slots are all filled" do
        expect(Pf2e.open_feat_slot_types(char('skill' => [ 'Assurance' ]))).to eq []
      end

      it "should keep a type that has one filled slot and one still open" do
        expect(Pf2e.open_feat_slot_types(char('skill' => [ 'Assurance', 'open' ]))).to eq [ 'skill' ]
      end

      it "should name every type that has something open" do
        types = Pf2e.open_feat_slot_types(char('skill' => [ 'open' ], 'charclass' => [ 'open' ],
                                               'general' => [ 'Toughness' ]))

        expect(types.sort).to eq [ 'charclass', 'skill' ]
      end

      it "should answer for a character owing no feats at all" do
        expect(Pf2e.open_feat_slot_types(char({}))).to eq []
      end

      it "should answer for a character with no feat pool recorded" do
        expect(Pf2e.open_feat_slot_types(double(:pf2_to_assign => {}, :name => 'Someone'))).to eq []
      end

      # The pool nests one level deeper for archetype slots, which are keyed by archetype name.
      it "should name a nested slot type with an open slot under it" do
        expect(Pf2e.open_feat_slot_types(char('archetype' => { 'Rogue' => [ 'open' ] }))).to eq [ 'archetype' ]
      end

      it "should leave out a nested slot type with nothing open" do
        expect(Pf2e.open_feat_slot_types(char('archetype' => { 'Rogue' => [ 'Sneak Attacker' ] }))).to eq []
      end
    end
  end
end
