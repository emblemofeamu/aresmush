require "aresmush"
require "yaml"
require "set"

module AresMUSH

  # Every key the code hands to `t` has to exist.
  #
  # Three of the eleven defects a twenty-player run turned up were this, and each reached the
  # player as "Translation missing: en.<key>": `pf2e.missing_alignment` and `pf2e.missing_deity`
  # were referenced and never written, and `pf2emagic.bad_search_syntax` was the message a
  # crash-guard was supposed to print. All three were one grep away.
  describe "a translation key" do

    ROOT = File.expand_path('..', __dir__)

    # Gaps in the base AresMUSH plugins this fork does not otherwise touch. Listed rather than
    # invented, because the wording is the game's own voice to choose - but listed here so a *new*
    # gap fails rather than joining them silently. Delete a line when its key is written.
    KNOWN_GAPS = %w{
      ansi.grayscale_mode_set
      area.area_not_found
      demographics.skill_census_title
      dispatcher.not_found
      fs3combat.invalid_vehicle
      login.web_registration_disabled
      mail.deleted_character
      page.cant_page_ignored
      rpprompts.showing_type
      webportal.only_switch_arescentral_alts
    }.to_set

    # Dotted keys, the way `t` asks for them.
    def self.flatten(node, prefix = [])
      return { prefix.join('.') => node } unless node.is_a?(Hash)

      node.flat_map { |key, value| flatten(value, prefix + [ key.to_s ]).to_a }.to_h
    end

    def self.locale_files
      Dir[File.join(ROOT, '{engine,plugins}', '**', 'locales', 'locale_en.yml')]
    end

    def self.defined_keys
      @defined_keys ||= locale_files.flat_map { |path| flatten(YAML.load_file(path)['en'] || {}).keys }.to_set
    end

    # `t('pf2e.foo')` and `t("pf2e.foo")`. A key built by interpolation or held in a variable is
    # invisible here, which is the limit of reading the source rather than running it.
    CALL = /\bt\(\s*['"]([a-zA-Z0-9_.]+)['"]/

    def self.used_keys
      @used_keys ||= Dir[File.join(ROOT, '{engine,plugins}', '**', '*.{rb,erb}')]
        .reject { |path| path =~ %r{/specs?/} }
        .flat_map do |path|
          File.readlines(path).each_with_index.flat_map do |line, index|
            next [] if line.strip.start_with?('#')

            line.scan(CALL).flatten.map { |key| [ key, "#{path.sub(ROOT + '/', '')}:#{index + 1}" ] }
          end
        end
    end

    it "should exist in the locale for every key the code asks for" do
      missing = self.class.used_keys
                    .reject { |key, _where| self.class.defined_keys.include?(key) || KNOWN_GAPS.include?(key) }
                    .map { |key, where| "#{where} asks for '#{key}'" }
                    .uniq.sort

      expect(missing).to eq []
    end

    # A gap that has since been written should come off the list, or the list stops meaning
    # anything and starts hiding the next one.
    it "should have no stale entries on the known-gaps list" do
      written = KNOWN_GAPS.select { |key| self.class.defined_keys.include?(key) }

      expect(written).to eq []
    end

    # A check that found nothing would pass for the wrong reason.
    it "should have found the keys the code actually uses" do
      expect(self.class.locale_files.size).to be > 20
      expect(self.class.used_keys.size).to be > 1000
      expect(self.class.defined_keys.size).to be > 500
    end
  end
end
