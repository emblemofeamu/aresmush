require "plugin_test_loader"
require_relative "support/auto_builder"

module AresMUSH
  module Pf2e

    # The Blessed background is house-ruled to grant Guidance as a divine innate cantrip, with no
    # GM-chosen blessing in its place. Chargen grants it from the background's config, beside whatever
    # the heritage grants; `BlessedBackground.migrate!` brings a character who took the background
    # before then onto the same shape.
    describe "the Blessed background", :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @made = []
      end

      after(:each) do
        @made.each do |made|
          live = Character[made.id]
          next unless live

          live.grants.each(&:delete)
          live.magic&.delete
          live.delete
        end
      end

      def built(background, ancestry: 'Khazad', heritage: 'Forge')
        char = Character.create(:name => "Blessed#{rand(1000000)}")
        @made << char

        AutoBuilder.new(char).build_level_one('Fighter', :ancestry => ancestry, :heritage => heritage,
                                                         :background => background)
        Character[char.id]
      end

      def approved(char)
        Roles.add_role(char, 'approved')
        Pf2e::Ledger.commit_chargen!(Character[char.id])
        Character[char.id]
      end

      def guidance(char)
        Pf2emagic::Entries.innate_for(Character[char.id].magic, 'Guidance')
      end

      describe "in chargen" do
        it "should grant Guidance as a divine innate cantrip cast with Charisma" do
          char = built('Blessed')

          expect(guidance(char).map { |g| g.slice('level', 'tradition', 'cast_stat') })
            .to eq [ { 'level' => 'cantrip', 'tradition' => 'divine', 'cast_stat' => 'Charisma' } ]
        end

        it "should no longer give the Blessed special ability" do
          expect(Array(built('Blessed').pf2_special)).to_not include 'Blessed'
        end

        it "should keep a heritage's innate spell beside it" do
          char = built('Blessed', :ancestry => 'Sildanyar', :heritage => 'Seer')
          names = Pf2emagic::Entries.innate_grants(char.magic).map { |g| g['name'] }

          expect(names).to contain_exactly('Detect Magic', 'Guidance')
        end

        it "should grant nothing for another background" do
          expect(guidance(built('Acolyte'))).to eq []
        end
      end

      describe "migrating a character who took it before" do

        # The shape the old background left: a "Blessed" special in the ledger, and no Guidance.
        def old_shape(char)
          magic = char.magic
          magic.update(:innate_spells => Array(magic.innate_spells).reject { |g| g['name'] == 'Guidance' })

          Pf2e::Ledger.write(char, :source_type => 'imported', :source_ref => 'old Blessed', :effective_level => 1) do |txn|
            txn.grant('add_special', 'special' => 'Blessed')
          end

          Character[char.id]
        end

        before(:each) do
          @char = old_shape(approved(built('Blessed')))
        end

        it "should start in the old shape" do
          expect(guidance(@char)).to eq []
          expect(@char.pf2_special).to include 'Blessed'
        end

        it "should grant Guidance" do
          BlessedBackground.migrate!(@char)

          expect(guidance(@char).size).to eq 1
          expect(guidance(@char).first['tradition']).to eq 'divine'
        end

        it "should take the special off, and keep it off through the next fold" do
          BlessedBackground.migrate!(@char)
          Pf2e::Ledger.invalidate!(Character[@char.id])
          Pf2e::Ledger.materialize!(Character[@char.id])

          expect(Character[@char.id].pf2_special).to_not include 'Blessed'
          expect(Pf2e::Ledger.explain_for(Character[@char.id], :kind => 'add_special', :key => 'Blessed')).to eq []
        end

        it "should change nothing the second time" do
          BlessedBackground.migrate!(@char)

          expect(BlessedBackground.migrate!(Character[@char.id])).to eq 0
          expect(guidance(@char).size).to eq 1
        end

        it "should take the special off a character still in chargen" do
          draft = built('Blessed')
          draft.update(:pf2_special => Array(draft.pf2_special) + [ 'Blessed' ])

          BlessedBackground.migrate!(Character[draft.id])

          expect(Character[draft.id].pf2_special).to_not include 'Blessed'
        end

        it "should leave a character with another background alone" do
          other = approved(built('Acolyte'))

          expect(BlessedBackground.migrate!(other)).to eq 0
          expect(guidance(other)).to eq []
        end

        it "should report each character it changed from migrate_all!" do
          result = BlessedBackground.migrate_all!(:characters => [ Character[@char.id] ])

          expect(result['changed']).to eq(@char.name => 2)
          expect(result['refused']).to eq({})
        end
      end
    end
  end
end
