require "plugin_test_loader"
require_relative "support/feat_matrix"

module AresMUSH
  module Pf2e

    # Taking a dedication, and taking a second one.
    #
    # PF2e's Dedication trait: "You cannot select another dedication feat until you have gained two
    # other feats from the [archetype] archetype." So the rule is per held dedication, counted in
    # non-dedication feats belonging to that dedication's archetype.
    #
    # The matrix runs a character holding one dedication and 0, 1, 2 and 3 of its archetype's feats
    # against a second dedication, and against feats of the archetype they already have. Two
    # dedications with the same archetype count separately, and a feat belonging to a different
    # archetype does not count towards either.
    describe "dedications" do
      include FeatMatrix

      # Two archetypes, each with a dedication and two ordinary feats, plus one feat belonging to a
      # third archetype so the matrix can check that counting is per archetype.
      def feat_config
        {
          'Alpha Dedication' => {
            'feat_type' => [ 'Charclass', 'Dedication' ],
            'assoc_archetype' => [ 'Alpha Archetype' ],
            'assoc_class' => [ 'Fighter', 'Wizard' ]
          },
          'Alpha Study' => {
            'feat_type' => [ 'Charclass' ], 'assoc_archetype' => [ 'Alpha Archetype' ],
            'prereq' => { 'feat' => [ 'Alpha Dedication' ] }
          },
          'Alpha Mastery' => {
            'feat_type' => [ 'Charclass' ], 'assoc_archetype' => [ 'Alpha Archetype' ],
            'prereq' => { 'feat' => [ 'Alpha Study' ] }
          },
          'Alpha Capstone' => {
            'feat_type' => [ 'Charclass' ], 'assoc_archetype' => [ 'Alpha Archetype' ],
            'prereq' => { 'feat' => [ 'Alpha Mastery' ], 'level' => 8 }
          },
          'Beta Dedication' => {
            'feat_type' => [ 'Charclass', 'Dedication' ],
            'assoc_archetype' => [ 'Beta Archetype' ],
            'assoc_class' => [ 'Fighter', 'Wizard' ]
          },
          'Beta Study' => {
            'feat_type' => [ 'Charclass' ], 'assoc_archetype' => [ 'Beta Archetype' ],
            'prereq' => { 'feat' => [ 'Beta Dedication' ] }
          },
          'Gamma Study' => {
            'feat_type' => [ 'Charclass' ], 'assoc_archetype' => [ 'Gamma Archetype' ]
          },
          # A dedication only a Cleric may take, for the assoc_class gate.
          'Cleric Only Dedication' => {
            'feat_type' => [ 'Charclass', 'Dedication' ],
            'assoc_archetype' => [ 'Delta Archetype' ],
            'assoc_class' => [ 'Cleric' ]
          },
          # A dedication with no assoc_class at all, which is the shape that reaches the
          # multiple-dedication rule through dedication_allowed?.
          'Open Dedication' => {
            'feat_type' => [ 'Charclass', 'Dedication' ],
            'assoc_archetype' => [ 'Epsilon Archetype' ]
          }
        }
      end

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_feats').and_return(feat_config)
        matrix_focus([])
      end

      def holding(*feats)
        matrix_char(:level => 10, :feats => { 'charclass' => feats.flatten })
      end

      describe "a first dedication" do
        it "should be allowed to a class on its list" do
          expect(matrix_allows?(matrix_char(:level => 2), 'Alpha Dedication')).to be true
        end

        it "should be refused to a class that is not on its list" do
          expect(matrix_allows?(matrix_char(:level => 2, :charclass => 'Cleric'), 'Alpha Dedication')).to be false
        end

        it "should be refused when the list names only another class" do
          expect(matrix_allows?(matrix_char(:level => 2), 'Cleric Only Dedication')).to be false
        end

        it "should be allowed to the class the list names" do
          expect(matrix_allows?(matrix_char(:level => 2, :charclass => 'Cleric'), 'Cleric Only Dedication')).to be true
        end
      end

      # The rule proper. Rows are the feats held from Alpha Archetype alongside Alpha Dedication.
      SECOND_DEDICATION = [
        { 'held' => [], 'allowed' => false, 'why' => 'no archetype feats yet' },
        { 'held' => [ 'Alpha Study' ], 'allowed' => false, 'why' => 'only one archetype feat' },
        { 'held' => [ 'Alpha Study', 'Alpha Mastery' ], 'allowed' => true, 'why' => 'two archetype feats' },
        { 'held' => [ 'Alpha Study', 'Alpha Mastery', 'Alpha Capstone' ], 'allowed' => true, 'why' => 'more than two' },
        { 'held' => [ 'Gamma Study' ], 'allowed' => false, 'why' => 'a feat of another archetype does not count' },
        { 'held' => [ 'Alpha Study', 'Gamma Study' ], 'allowed' => false, 'why' => 'one of each is still one' }
      ].freeze

      describe "a second dedication" do
        SECOND_DEDICATION.each do |row|
          it "should be #{row['allowed'] ? 'allowed' : 'refused'} with #{row['why']}" do
            char = holding('Alpha Dedication', row['held'])

            expect(Pf2e.dedication_archetype_ready?(char)).to eq row['allowed']
          end
        end

        it "should not count the dedication itself towards its own two feats" do
          char = holding('Alpha Dedication')

          expect(Pf2e.dedication_archetype_ready?(char)).to be false
        end

        it "should require two feats for every dedication held, not just one of them" do
          # Alpha is satisfied and Beta is not, so a third dedication is still refused.
          char = holding('Alpha Dedication', 'Alpha Study', 'Alpha Mastery', 'Beta Dedication')

          expect(Pf2e.dedication_archetype_ready?(char)).to be false
        end

        it "should allow a third once both held dedications have their two" do
          char = holding('Alpha Dedication', 'Alpha Study', 'Alpha Mastery',
                         'Beta Dedication', 'Beta Study', 'Gamma Study')

          # Beta has only Beta Study, so this is still short.
          expect(Pf2e.dedication_archetype_ready?(char)).to be false
        end
      end

      # The rule has to bite on every path that can hand over a dedication, not only on the one
      # where a player types the feat name.
      describe "every path that can grant a dedication" do
        def ready_char
          holding('Alpha Dedication', 'Alpha Study', 'Alpha Mastery')
        end

        def unready_char
          holding('Alpha Dedication')
        end

        it "should refuse a second dedication through a choice pool while the first is unready" do
          pool = Pf2e.choice_feat_pool(unready_char, 'feat_type' => [ 'charclass' ])

          expect(pool).to_not include 'Beta Dedication'
        end

        it "should offer a second dedication through a choice pool once the first is ready" do
          pool = Pf2e.choice_feat_pool(ready_char, 'feat_type' => [ 'charclass' ])

          expect(pool).to include 'Beta Dedication'
        end

        it "should refuse a second dedication by name while the first is unready" do
          expect(matrix_allows?(unready_char, 'Beta Dedication')).to be false
        end

        it "should allow a second dedication by name once the first is ready" do
          expect(matrix_allows?(ready_char, 'Beta Dedication')).to be true
        end
      end

      # An archetype's own feats chain back to its dedication, which is what stops a character
      # taking an archetype's later feats without joining the archetype.
      describe "an archetype's feat chain" do
        CHAIN = [
          { 'feat' => 'Alpha Study', 'held' => [], 'allowed' => false },
          { 'feat' => 'Alpha Study', 'held' => [ 'Alpha Dedication' ], 'allowed' => true },
          { 'feat' => 'Alpha Mastery', 'held' => [ 'Alpha Dedication' ], 'allowed' => false },
          { 'feat' => 'Alpha Mastery', 'held' => [ 'Alpha Dedication', 'Alpha Study' ], 'allowed' => true },
          { 'feat' => 'Alpha Capstone', 'held' => [ 'Alpha Dedication', 'Alpha Study', 'Alpha Mastery' ], 'allowed' => true }
        ].freeze

        CHAIN.each do |row|
          it "should #{row['allowed'] ? 'allow' : 'refuse'} #{row['feat']} holding #{row['held'].size} of the chain" do
            char = holding(row['held'])

            expect(matrix_allows?(char, row['feat'])).to eq row['allowed']
          end
        end

        it "should refuse the capstone below its level even with the whole chain" do
          char = matrix_char(:level => 7,
                             :feats => { 'charclass' => [ 'Alpha Dedication', 'Alpha Study', 'Alpha Mastery' ] })

          expect(matrix_allows?(char, 'Alpha Capstone')).to be false
        end
      end
    end
  end
end
