require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The PF2e Player Core progression, encoded so the class tables can be checked against it.
    #
    # Ancestry feats at 1, 5, 9, 13, 17; general feats at 3, 7, 11, 15, 19; class and skill
    # feats at even levels; skill increases at 3, 5, 7 … 19; four attribute boosts at 5, 10,
    # 15, 20. Level 1's ancestry feat comes from chargen, so a class table carries four.
    # Sources are cited in docs/pf2e-progression-reference.md.
    describe "class advancement tables" do

      EXPECTED_FEATS = {
        'charclass' => [ 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 ],
        'skill' => [ 2, 4, 6, 8, 10, 12, 14, 16, 18, 20 ],
        'general' => [ 3, 7, 11, 15, 19 ],
        'ancestry' => [ 5, 9, 13, 17 ]
      }.freeze

      EXPECTED_SKILL_INCREASES = [ 3, 5, 7, 9, 11, 13, 15, 17, 19 ].freeze
      EXPECTED_BOOSTS = [ 5, 10, 15, 20 ].freeze

      # Classes whose progression deliberately differs, per their own AoN class tables.
      SKILL_FEAT_EVERY_LEVEL = [ 'Rogue' ].freeze
      SKILL_INCREASE_EVERY_LEVEL = [ 'Rogue', 'Investigator' ].freeze

      # Known deviations in this fork's config, recorded as pending so that fixing one turns
      # the example green and RSpec reports it. See finding 17 in
      # docs/pathfinder-2e-in-emblem-of-ea.md.
      KNOWN_DEVIATIONS = {
        'Investigator' => 'level 19 grants an ancestry feat where PF2e grants a general feat',
        'Monk' => 'level 19 grants an ancestry feat where PF2e grants a general feat',
        'Oracle' => 'level 19 grants an ancestry feat where PF2e grants a general feat',
        'Ranger' => 'level 19 grants an ancestry feat where PF2e grants a general feat',
        'Rogue' => 'level 19 grants an ancestry feat where PF2e grants a general feat',
        'Sorcerer' => 'level 19 grants an ancestry feat where PF2e grants a general feat',
        'Witch' => 'level 19 grants an ancestry feat where PF2e grants a general feat',
        'Druid' => 'level 13 grants a general feat where PF2e grants an ancestry feat',
        'Cleric' => 'level 17 swaps ancestry for general, and level 20 grants a general feat where a class feat belongs'
      }.freeze

      def self.class_names
        (Global.read_config('pf2e_class') || {}).keys.sort
      end

      def feats_by_type(charclass)
        table = (Global.read_config('pf2e_class', charclass, 'advance') || {})
        found = {}

        table.each_pair do |level, data|
          next unless data.is_a?(Hash)

          Array(data['choose_feat']).each do |type|
            key = type.to_s.downcase
            (found[key] ||= []) << level.to_i
          end
        end

        found.each_value(&:sort!)
        found
      end

      def raises_of(charclass, kind)
        table = (Global.read_config('pf2e_class', charclass, 'advance') || {})

        table.select do |_level, data|
          next false unless data.is_a?(Hash)
          Array(data['raise']).any? { |item| item.to_s.downcase == kind }
        end.keys.map(&:to_i).sort
      end

      class_names.each do |charclass|
        context charclass do
          it "should grant class feats at even levels" do
            pending KNOWN_DEVIATIONS[charclass] if charclass == 'Cleric'

            expect(feats_by_type(charclass)['charclass']).to eq EXPECTED_FEATS['charclass']
          end

          it "should grant skill feats on the PF2e schedule" do
            expected = SKILL_FEAT_EVERY_LEVEL.include?(charclass) ? (2..20).to_a : EXPECTED_FEATS['skill']

            expect(feats_by_type(charclass)['skill']).to eq expected
          end

          it "should grant general feats at 3, 7, 11, 15 and 19" do
            pending KNOWN_DEVIATIONS[charclass] if KNOWN_DEVIATIONS.key?(charclass)

            expect(feats_by_type(charclass)['general']).to eq EXPECTED_FEATS['general']
          end

          it "should grant ancestry feats at 5, 9, 13 and 17" do
            pending KNOWN_DEVIATIONS[charclass] if KNOWN_DEVIATIONS.key?(charclass)

            expect(feats_by_type(charclass)['ancestry']).to eq EXPECTED_FEATS['ancestry']
          end

          it "should grant skill increases on the PF2e schedule" do
            expected = SKILL_INCREASE_EVERY_LEVEL.include?(charclass) ? (2..20).to_a : EXPECTED_SKILL_INCREASES

            expect(raises_of(charclass, 'skill')).to eq expected
          end

          it "should grant four attribute boosts at 5, 10, 15 and 20" do
            expect(raises_of(charclass, 'ability')).to eq EXPECTED_BOOSTS
          end
        end
      end
    end
  end
end
