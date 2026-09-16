module AresMUSH
  module Pf2e

    # Config access for a pure core.
    #
    # In the game this delegates to Global.read_config; in a spec it wraps a fixture hash,
    # so a core can be tested against six lines of YAML-shaped data instead of the 2 MB of
    # pf2e_*.yml the game loads at boot.
    #
    #   view = ConfigView.fixture('pf2e_class' => { 'Wizard' => { 'HP' => 6 } })
    #   view.read('pf2e_class', 'Wizard', 'HP')   # => 6
    class ConfigView

      def self.live
        new(nil)
      end

      def self.fixture(hash)
        new(hash || {})
      end

      def initialize(fixture)
        @fixture = fixture
      end

      def live?
        @fixture.nil?
      end

      # Returns nil for any missing or non-hash path, matching Global.read_config's habit of
      # answering nil rather than raising - which is why callers everywhere write `|| []`.
      def read(*path)
        return Global.read_config(*path) if live?

        path.reduce(@fixture) do |node, key|
          return nil unless node.is_a?(Hash)
          node[key]
        end
      end
    end
  end
end
