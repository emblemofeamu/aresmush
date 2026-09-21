require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # Choosing the spell an innate grant left open, during a level-up.
    #
    # The grant is recorded twice while the level is open: as the pending entry in the draft's
    # magic_stats, which is what `advance/done` hands to the magic object, and as a slot in the
    # pool, which is what the review screen counts.
    describe "advance/spell innate", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Innate#{rand(1000000)}")
        @magic = PF2Magic.create(:character => @char)
        @char.update(:magic => @magic)

        @char.update(:pf2_level => 4,
                     :advancing => true,
                     :pf2_base_info => { 'charclass' => 'Fighter', 'ancestry' => 'Human' },
                     :pf2_to_assign => { 'innate' => { 'cantrip' => [ 'open' ] } },
                     :pf2_advancement => {
                       'magic_stats' => {
                         'innate_spell' => { 'name' => 'open', 'level' => 'cantrip', 'tradition' => 'divine' }
                       }
                     })

        @builder = AutoBuilder.new(Character[@char.id])
      end

      after(:each) do
        @magic.delete if @magic
        @char.delete if @char
      end

      def pick(spell)
        @builder.run "advance/spell innate/cantrip=#{spell}"
      end

      # Whatever divine cantrip the shipped data holds, so the spec does not pin a spell name.
      def a_divine_cantrip
        Pf2emagic.find_common_spells.find do |_name, details|
          Array(details['tradition']).any? { |t| t.to_s.casecmp?('divine') } &&
            Array(details['traits']).any? { |t| t.to_s.casecmp?('cantrip') }
        end&.first
      end

      it "should record the spell against the pending grant" do
        spell = a_divine_cantrip

        expect(spell).to_not be_nil

        char = pick(spell)

        expect(@builder.failures).to be_empty
        expect(char.pf2_advancement['magic_stats']['innate_spell']['name']).to eq spell
      end

      it "should spend the slot it came from" do
        char = pick(a_divine_cantrip)

        expect(Array(char.pf2_to_assign['innate']['cantrip'])).to_not include 'open'
      end
    end
  end
end
