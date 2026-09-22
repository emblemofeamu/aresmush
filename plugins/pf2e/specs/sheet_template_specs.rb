require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What the sheet does with a bucket that is not there.
    #
    # `pf2_features` starts as two empty buckets, but the materialiser rebuilds it from the fold and
    # the fold only makes a bucket that has something in it. So a character with no archetype has no
    # 'archetype_features' key after their first commit, and the sheet asked it for `.empty?`.
    describe Pf2eSheetTemplate do

      def rendered_for(features)
        char = double(:pf2_features => features, :pf2_archetypeinfo => {})
        template = Pf2eSheetTemplate.allocate

        template.instance_variable_set(:@char, char)
        template
      end

      it "should say None for a bucket the fold never made" do
        template = rendered_for('charclass_features' => [ 'Rage' ])

        expect(template.archetype_features).to eq 'None'
        expect(template.class_features).to eq 'Rage'
      end

      it "should say None for an empty bucket" do
        template = rendered_for('charclass_features' => [], 'archetype_features' => [])

        expect(template.class_features).to eq 'None'
        expect(template.archetype_features).to eq 'None'
      end

      it "should list what a bucket holds, in order" do
        template = rendered_for('charclass_features' => [ 'Rage', 'Bravery' ],
                                'archetype_features' => [ 'Basic Bard Spellcasting' ])

        expect(template.class_features).to eq 'Bravery, Rage'
        expect(template.archetype_features).to eq 'Basic Bard Spellcasting'
      end

      it "should cope with no features hash at all" do
        expect(rendered_for(nil).class_features).to eq 'None'
      end
    end
  end
end
