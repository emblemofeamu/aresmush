require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Which heading a feat belongs under.
    #
    # Chargen filed every feat a class, specialty or specialty option granted under `charclass`,
    # whatever the feat actually was, so a Fighter's Shield Block - a *general* feat - showed up
    # among their class feats, as did the Alchemist's Alchemical Crafting and the Swashbuckler's
    # Fascinating Performance, both skill feats. Nothing mechanical depended on it, because every
    # prerequisite and duplicate check reads `pf2_feats.values.flatten`, but the sheet reads the
    # buckets.
    describe :feat_bucket_for do

      it "should put a general feat under general" do
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(
          'Shield Block' => { 'feat_type' => [ 'General' ] }
        )

        expect(Pf2e.feat_bucket_for('Shield Block')).to eq 'general'
      end

      it "should put a class feat under charclass" do
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(
          'Power Attack' => { 'feat_type' => [ 'Charclass' ] }
        )

        expect(Pf2e.feat_bucket_for('Power Attack')).to eq 'charclass'
      end

      # Alchemical Crafting is Skill and General; the more specific heading is the one to use.
      it "should prefer the first type for a feat that is more than one" do
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(
          'Alchemical Crafting' => { 'feat_type' => [ 'Skill', 'General' ] }
        )

        expect(Pf2e.feat_bucket_for('Alchemical Crafting')).to eq 'skill'
      end

      it "should match the feat however it was capitalised" do
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(
          'Shield Block' => { 'feat_type' => [ 'General' ] }
        )

        expect(Pf2e.feat_bucket_for('shield block')).to eq 'general'
      end

      it "should fall back to charclass for a feat the data does not describe" do
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return({})

        expect(Pf2e.feat_bucket_for('Invented Feat')).to eq 'charclass'
      end

      it "should fall back to charclass for a type that is not a heading" do
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(
          'Odd One' => { 'feat_type' => [ 'Mystery' ] }
        )

        expect(Pf2e.feat_bucket_for('Odd One')).to eq 'charclass'
      end

      describe :bucket_feats do
        it "should group a list of granted feats by where each belongs" do
          allow(Global).to receive(:read_config).with('pf2e_feats').and_return(
            'Shield Block' => { 'feat_type' => [ 'General' ] },
            'Power Attack' => { 'feat_type' => [ 'Charclass' ] },
            'Alchemical Crafting' => { 'feat_type' => [ 'Skill', 'General' ] }
          )

          grouped = Pf2e.bucket_feats([ 'Shield Block', 'Power Attack', 'Alchemical Crafting' ])

          expect(grouped).to eq(
            'general' => [ 'Shield Block' ],
            'charclass' => [ 'Power Attack' ],
            'skill' => [ 'Alchemical Crafting' ]
          )
        end

        it "should give nothing for no feats" do
          expect(Pf2e.bucket_feats([])).to eq({})
        end
      end
    end
  end
end
