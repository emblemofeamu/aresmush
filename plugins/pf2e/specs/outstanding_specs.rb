require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # What a level-up still owes the player.
    #
    # One question with two readers: advance/review lists it as messages, advance/info lists it as
    # labels a player can type. Both go through Advancement::Outstanding, so a key that opens a
    # pick cannot be visible to one and invisible to the other.
    describe Advancement::Outstanding do

      before(:each) do
        stub_translate_for_testing
        allow(Pf2e).to receive(:find_choice_block).and_return(nil)
        allow(Pf2e).to receive(:choice_summary).and_return('an option')
      end

      def char_with(to_assign)
        double(:pf2_to_assign => to_assign, :pf2_advancement => {}, :name => 'Someone',
               :pf2_level => 5, :pf2_base_info => { 'charclass' => 'Wizard' })
      end

      def state(to_assign)
        CharState.build({ 'to_assign' => to_assign }, :config => ConfigView.fixture({}))
      end

      def messages(to_assign)
        Array(Pf2e.advancement_messages(char_with(to_assign)))
      end

      def labels(to_assign)
        Advancement::Outstanding.labels(state(to_assign))
      end

      # Each row: the draft as it looks with that pick still open, and the label a player types at
      # advance/info to see it.
      PENDING = {
        'feats' => [ { 'feats' => { 'charclass' => [ 'open' ] } }, 'charclass feat' ],
        'class option' => [ { 'class option' => { 'Arcane Bond' => [ 'a', 'b' ] } }, 'Arcane Bond' ],
        'feat choice' => [ { 'feat choice' => { 'Assurance' => [ 'open' ] } }, 'Assurance' ],
        'raise skill' => [ { 'raise skill' => [ 'open' ] }, nil ],
        'raise ability' => [ { 'raise ability' => [ 'open' ] }, nil ],
        'raise skill choice' => [ { 'raise skill choice' => [ 'Arcana' ] }, nil ],
        'open languages' => [ { 'open languages' => [ 'open' ] }, nil ],
        'spellbook' => [ { 'spellbook' => { '1' => [ 'open' ] } }, nil ],
        'repertoire' => [ { 'repertoire' => { '1' => [ 'open' ] } }, nil ],
        'innate' => [ { 'innate' => { '1' => [ 'open' ] } }, nil ],
        'signature' => [ { 'signature' => { '1' => 1 } }, nil ],
        'archetype_specialty' => [ { 'archetype_specialty' => 'open' }, nil ],
        'archetype specialty choice' => [ { 'archetype specialty choice' => { 'Pirate' => { 'choice' => 'open' } } }, nil ],
        'archetype key ability' => [ { 'archetype key ability' => 'open' }, nil ],
        'archetype deity' => [ { 'archetype deity' => 'open' }, nil ],
        'archetype_sanctification' => [ { 'archetype_sanctification' => 'open' }, nil ],
        'grants' => [ { 'grants' => { 'Counterspell' => {} } }, 'Counterspell' ]
      }.freeze

      describe "every key that can hold an open pick" do
        PENDING.each_pair do |key, (to_assign, label)|
          it "should report #{key} as outstanding" do
            expect(Advancement::Outstanding.any?(state(to_assign))).to be true
          end

          it "should name #{key} so advance/info can describe it" do
            next if label.nil?

            expect(labels(to_assign)).to include label
          end

          it "should not offer #{key} as an advance/info element it cannot answer" do
            next unless label.nil?

            expect(labels(to_assign)).to be_empty
          end

          it "should say so on the review screen too" do
            expect(messages(to_assign)).to_not be_empty
          end
        end
      end

      it "should owe both picks when two slot spellings each hold one" do
        to_assign = { 'class option' => { 'Arcane Bond' => [ 'a', 'b' ] },
                      'charclass option' => { 'Arcane Thesis' => [ 'c', 'd' ] } }

        expect(labels(to_assign)).to eq [ 'Arcane Bond', 'Arcane Thesis' ]
        expect(messages(to_assign).size).to eq 2
      end

      it "should report nothing outstanding for an empty draft" do
        expect(Advancement::Outstanding.any?(state({}))).to be false
        expect(messages({})).to be_empty
      end

      it "should treat a resolved pick as settled" do
        expect(Advancement::Outstanding.any?(state('feats' => { 'charclass' => [ 'Counterspell' ] }))).to be false
        expect(messages('feats' => { 'charclass' => [ 'Counterspell' ] })).to be_empty
      end

      # A key with no entry renders as the raw key to the player, and this table is what the review
      # screen and advance/done both speak through.
      it "should have a locale entry for every message it can emit" do
        locale = YAML.load_file(File.join(Pf2e.plugin_dir, 'locales', 'locale_en.yml'))['en']['pf2e']
        keys = PENDING.values.flat_map do |(to_assign, _label)|
          Advancement::Outstanding.messages(state(to_assign)).map { |(key, _args)| key }
        end.uniq

        expect(keys.reject { |key| locale.key?(key.sub('pf2e.', '')) }).to eq []
      end

      it "should cover every key a draft can hold" do
        holders = DraftKeys::KEYS.select { |_k, (holder, _d)| holder == DraftKeys::TO_ASSIGN }.keys

        # The keys that are records of a pick rather than a pick still to make.
        # Records of a pick already made, and 'open skills', which is chargen's - a free skill
        # increase at a level lands in 'raise skill'.
        settled = [ 'open skills', 'feat choice filter', 'feat_choices', 'bgskill', 'bg_lore', 'bgfeat',
                    'bg skill choice', 'class skill choice', 'specialty skill choice',
                    'ancestry feat', 'charclass feat', 'skill feat', 'general feat',
                    'archetype feat', 'dedication feat', 'divine font', 'archetype',
                    'archetype sanctification' ]

        expect(holders - settled - PENDING.keys).to eq []
      end
    end
  end
end
