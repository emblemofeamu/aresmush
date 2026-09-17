require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      # What a finished level-up writes to the sheet.
      #
      # One row per draft key, so a key the draft can hold but nothing applies is a failing spec
      # rather than a level that quietly loses a pick.
      describe Apply do

        it "should have a row for every key a level-up draft can hold" do
          holders = [ DraftKeys::ADVANCEMENT, DraftKeys::BOTH ]
          advancement = DraftKeys::KEYS.select { |_k, (holder, _d)| holders.include?(holder) }.keys

          expect(advancement - Apply.keys).to eq []
        end

        # start_advancement copies a level block's keys it does not otherwise handle straight into
        # the draft, so what a class table can say is also what has to be applicable. This is the
        # check that a level giving something nothing applies would otherwise pass silently: the
        # Bard's 7th-level tradition raise did exactly that.
        it "should have a row for every key a class table puts in the draft" do
          handled_at_start = %w{choose_feat feat_choice grant_choice raise choose charclass_choice}

          keys = [ 'pf2e_class', 'pf2e_archetype', 'pf2e_specialty' ].flat_map do |section|
            level_block_keys(Global.read_config(section))
          end.uniq - handled_at_start

          expect(keys - Apply.keys).to eq []
        end

        # Every key inside a numbered level block, however deep the file nests the tables.
        def level_block_keys(node)
          return [] unless node.is_a?(Hash)

          node.flat_map do |key, value|
            own = key.to_s.match?(/\A\d+\z/) && value.is_a?(Hash) ? value.keys.map(&:to_s) : []

            own + level_block_keys(value)
          end
        end

        it "should log a key nothing applies, and say so out of character" do
          char = double(:name => 'Someone')

          expect(Global.logger).to receive(:error).with(/nothing applies/)

          messages = Apply.all(char, { 'nonsense' => true }, :charclass => 'Wizard', :client => nil)

          expect(messages.first[0]).to eq 'pf2e.adv_unknown_draft_key'
          expect(messages.first[2]).to eq :ooc
        end

        describe "filing spells by rank" do
          it "should keep a draft already keyed by rank" do
            expect(Apply.ranked('1' => [ 'Magic Missile' ])).to eq('1' => [ 'Magic Missile' ])
          end

          it "should file a flat list by each spell's own rank" do
            allow(Pf2emagic).to receive(:get_spell_details).with('Fireball')
              .and_return([ 'Fireball', { 'base_level' => 3 } ])

            expect(Apply.ranked([ 'Fireball' ])).to eq('3' => [ 'Fireball' ])
          end

          it "should file a spell it cannot identify at the first rank" do
            allow(Pf2emagic).to receive(:get_spell_details).and_return('no such spell')

            expect(Apply.ranked([ 'Nonsense' ])).to eq('1' => [ 'Nonsense' ])
          end
        end

        describe "whose list a pick belongs to" do
          it "should read a rank-keyed draft as the character's own class" do
            picks = Apply.by_class(:value => { '1' => [ 'Magic Missile' ] }, :charclass => 'Wizard')

            expect(picks).to eq('Wizard' => { '1' => [ 'Magic Missile' ] })
          end

          it "should read a class-keyed draft as it is written" do
            picks = Apply.by_class(:value => { 'Bard Archetype' => { '1' => [ 'Soothe' ] } }, :charclass => 'Wizard')

            expect(picks).to eq('Bard Archetype' => { '1' => [ 'Soothe' ] })
          end
        end
      end
    end
  end
end
