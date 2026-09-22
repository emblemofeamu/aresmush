require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a feat's `grants` block can hand over.
    #
    # One row per key, so the vocabulary is readable in one place and a key the config uses but the
    # table does not have is a failing spec rather than a sentence shown to a player.
    describe "a feat's grants" do

      # Every subkey the shipped config uses under a `grants:` block, so config and table cannot
      # drift: a feat granting something nothing applies would be silently inert.
      def config_grant_keys
        feats = %w{pf2e_feats pf2e_feat_ancestry pf2e_feat_class pf2e_feat_general pf2e_feat_skill
                   pf2e_feat_archetype pf2e_class pf2e_specialty pf2e_archetypes pf2e_background
                   pf2e_ancestry pf2e_heritage}

        feats.flat_map { |file| grant_keys_in(Global.read_config(file)) }.uniq.compact
      end

      # Every key under every 'grants' hash, however deeply the file nests them.
      def grant_keys_in(node)
        return [] unless node.is_a?(Hash)

        node.flat_map do |key, value|
          nested = grant_keys_in(value)

          key.to_s == 'grants' && value.is_a?(Hash) ? nested + value.keys.map(&:to_s) : nested
        end
      end

      it "should have a row for every key the config grants" do
        expect(config_grant_keys - Pf2e.grant_keys).to eq []
      end

      it "should say when each key is resolved" do
        expect(Pf2e::GRANTS.values.map { |row| row['timing'] }.uniq.sort).to eq %w(advance assign)
      end

      describe :assess_feat_grants do
        it "should split a block into what is picked now and what waits for the level" do
          split = Pf2e.assess_feat_grants('assign' => [ 'open languages' ], 'skill' => [ 'Arcana' ])

          expect(split['assign']).to eq('assign' => [ 'open languages' ])
          expect(split['advance']).to eq('skill' => [ 'Arcana' ])
        end

        it "should treat a key it does not know as one to apply when the level commits" do
          split = Pf2e.assess_feat_grants('mystery_key' => true)

          expect(split['advance']).to eq('mystery_key' => true)
        end

        it "should answer with both halves for an empty block" do
          expect(Pf2e.assess_feat_grants(nil)).to eq('assign' => {}, 'advance' => {})
        end
      end

      describe "a key with no row" do
        it "should be logged rather than shown to the player" do
          char = double(:name => 'Someone')

          expect(Global.logger).to receive(:error).with(/not one of/)
          expect(Pf2e.do_feat_grants(char, { 'nonsense' => true }, 'Fighter', nil)).to eq []
        end
      end

      describe "every message it can emit" do
        it "should have a locale entry" do
          locale = YAML.load_file(File.join(Pf2e.plugin_dir, 'locales', 'locale_en.yml'))['en']['pf2e']
          used = File.read(File.join(Pf2e.plugin_dir, 'helpers', 'feats.rb'))
                     .scan(/'pf2e\.(feat_grants_[a-z_]+|feat_needs_free_skill)'/).flatten.uniq

          expect(used.reject { |key| locale.key?(key) }).to eq []
        end
      end
    end
  end
end
