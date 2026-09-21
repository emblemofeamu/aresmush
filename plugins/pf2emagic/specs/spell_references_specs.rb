require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # A spell the config promises has to be a spell the catalogue defines.
    #
    # Thirteen cleric domains named a focus spell that was never in the data - twelve of them both
    # their initial and their advanced - so a Cleric who chose one was granted a spell the game
    # could not give them. Nothing checked, because nothing reads the two files together.
    describe "a spell the config refers to" do

      # The keys that hold spell names rather than counts, ranks or traditions.
      SPELL_KEYS = %w{initial advanced devotion_spells}.freeze

      def catalogue
        @catalogue ||= Dir[File.join(AresMUSH.game_path, 'config', '*spell*.yml')]
                       .each_with_object({}) { |path, all| all.merge!(YAML.load_file(path)['pf2e_spells'] || {}) }
      end

      def known?(name)
        catalogue.keys.any? { |spell| spell.casecmp?(name.to_s) }
      end

      # Every (where, spell name) pair the magic config names.
      def referenced
        found = []

        walk = lambda do |node, trail|
          next unless node.is_a?(Hash)

          node.each_pair do |key, value|
            if SPELL_KEYS.include?(key.to_s)
              Array(value).flatten.each { |name| found << [ trail.join(' > '), name ] if name.is_a?(String) && !name.strip.empty? }
            end

            walk.call(value, trail + [ key ])
          end
        end

        walk.call(YAML.load_file(File.join(AresMUSH.game_path, 'config', 'pf2e_magic.yml')), [])
        found
      end

      it "should be in the spell catalogue" do
        missing = referenced.reject { |_where, name| known?(name) }
                            .map { |where, name| "#{where} names '#{name}'" }
                            .uniq.sort

        expect(missing).to eq []
      end

      # A check that found nothing would pass for the wrong reason.
      it "should have found the domains to check" do
        expect(referenced.size).to be > 50
        expect(catalogue.size).to be > 600
      end
    end
  end
end
