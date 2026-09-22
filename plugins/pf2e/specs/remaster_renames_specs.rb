require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The shipped data uses Remaster names and players arrive with the pre-Remaster ones. A lookup
    # that misses checks this table before telling them the name is not in the game.
    describe Renames do

      def table
        {
          'Magic Missile'    => { 'status' => 'renamed', 'to' => 'Force Barrage' },
          'Burning Hands'    => { 'status' => 'renamed', 'to' => 'Breathe Fire' },
          'Dancing Lights'   => { 'status' => 'merged',  'to' => 'Light' },
          'Glyph of Warding' => { 'status' => 'renamed', 'to' => 'Rune Trap' },
          'Divine Vessel'    => { 'status' => 'removed' }
        }
      end

      # Rune Trap is deliberately absent, so the answer has to distinguish "renamed to something
      # you can take" from "renamed to something this game does not stock".
      def stocked
        [ 'Force Barrage', 'Breathe Fire', 'Light' ]
      end

      describe :lookup do
        it "should find a legacy name however the player capitalised it" do
          expect(Renames.lookup('mAGIC mISSILE', table)).to eq [ 'Magic Missile', table['Magic Missile'] ]
        end

        it "should ignore surrounding whitespace" do
          expect(Renames.lookup('  Burning Hands ', table).first).to eq 'Burning Hands'
        end

        it "should not answer for a name that was never renamed" do
          expect(Renames.lookup('Fireball', table)).to be_nil
        end
      end

      describe :message do
        def key_for(name)
          Renames.message(name, table[name], stocked).first
        end

        it "should tell a rename apart from a merge" do
          expect(key_for('Magic Missile')).to_not eq key_for('Dancing Lights')
        end

        it "should tell a replacement this game stocks apart from one it does not" do
          expect(key_for('Magic Missile')).to_not eq key_for('Glyph of Warding')
        end

        it "should carry both names, so the player can see which of theirs was stale" do
          _key, args = Renames.message('Magic Missile', table['Magic Missile'], stocked)

          expect(args[:old]).to eq 'Magic Missile'
          expect(args[:new]).to eq 'Force Barrage'
        end

        it "should still name a replacement this game does not stock, so the player stops looking" do
          _key, args = Renames.message('Glyph of Warding', table['Glyph of Warding'], stocked)

          expect(args[:new]).to eq 'Rune Trap'
        end

        it "should offer no replacement for a name that was removed" do
          _key, args = Renames.message('Divine Vessel', table['Divine Vessel'], stocked)

          expect(args[:new]).to be_nil
        end

        it "should have a translation for every status the table can hold" do
          rendered = table.map { |name, row| Renames.describe_one(name, row, stocked) }

          expect(rendered.select { |line| line.to_s.strip.empty? || line.to_s.downcase.include?('translation missing') }).to eq []
        end
      end

      describe :near do
        it "should find legacy names that contain the term" do
          expect(Renames.near('hands', table)).to eq [ 'Burning Hands' ]
        end

        it "should not match on a fragment too short to mean anything" do
          expect(Renames.near('of', table)).to eq []
        end

        it "should leave out a name that matches exactly, which lookup already answered" do
          expect(Renames.near('Magic Missile', table)).to eq []
        end
      end

      describe :hint do
        it "should name what the spell became" do
          expect(Renames.hint('Magic Missile', table, stocked)).to include 'Force Barrage'
        end

        it "should name the replacement of a near match, not just the stale name" do
          near = Renames.hint('Hands', table, stocked)

          expect(near).to include 'Burning Hands'
          expect(near).to include 'Breathe Fire'
        end

        it "should say nothing at all about a name the table does not hold" do
          expect(Renames.hint('Fireball', table, stocked)).to be_nil
        end

        it "should prefer the exact answer over a list of near ones" do
          # 'Divine Vessel' is exact; nothing else contains it.
          expect(Renames.hint('Divine Vessel', table, stocked)).to include 'Divine Vessel'
        end
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # What a player gets for typing a feat name the catalogue does not hold. A pre-Remaster name
    # is the common case, and "check your spelling" is the wrong answer to it.
    describe :bad_feat_message do

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_feats')
          .and_return({ 'Celestial Mercy' => {}, 'Nimble Dodge' => {} })
        allow(Global).to receive(:read_config).with('pf2e_renames', 'feats')
          .and_return({ "Aasimar's Mercy" => { 'status' => 'renamed', 'to' => 'Celestial Mercy' },
                        'Aura of Unbreakable Virtue' => { 'status' => 'removed' } })
      end

      it "should name the feat a renamed one became" do
        expect(Pf2e.bad_feat_message("Aasimar's Mercy")).to include 'Celestial Mercy'
      end

      it "should say a removed feat is gone rather than blaming the spelling" do
        message = Pf2e.bad_feat_message('Aura of Unbreakable Virtue')

        expect(message).to include 'removed'
        expect(message).to_not include 'spelling'
      end

      it "should fall back to the spelling advice for a name the table has never heard of" do
        expect(Pf2e.bad_feat_message('Xyzzy')).to include 'spelling'
      end

      # Every command that resolves a feat name routes its failure through one place, so the
      # answer to an ambiguous term stays the list of what it matched.
      describe "for each way a lookup can fail" do
        it "should list the matches behind an ambiguous term" do
          allow(Global).to receive(:read_config).with('pf2e_feats')
            .and_return({ 'Nimble Dodge' => {}, 'Nimble Roll' => {} })

          message = Pf2e.feat_lookup_failure('Nimble', 'ambiguous')

          expect(message).to include 'Nimble Dodge'
          expect(message).to include 'Nimble Roll'
        end

        it "should answer a name that matched nothing with where it went" do
          expect(Pf2e.feat_lookup_failure("Aasimar's Mercy", 'no_match')).to include 'Celestial Mercy'
        end
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # The three commands a player reaches for when a name does not work: look the feat up, search
    # for it, search for the spell. Each of them used to end at "nothing to display".
    describe "a lookup that finds nothing" do

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_feats')
          .and_return({ 'Celestial Mercy' => { 'traits' => [], 'shortdesc' => '' } })
        allow(Global).to receive(:read_config).with('pf2e_renames', 'feats')
          .and_return({ "Aasimar's Mercy" => { 'status' => 'renamed', 'to' => 'Celestial Mercy' } })
        allow(Global).to receive(:read_config).with('pf2e_spells')
          .and_return({ 'Force Barrage' => { 'traits' => [] } })
        allow(Global).to receive(:read_config).with('pf2e_renames', 'spells')
          .and_return({ 'Magic Missile' => { 'status' => 'renamed', 'to' => 'Force Barrage' } })
      end

      def failure_from(handler)
        said = nil
        client = double
        allow(client).to receive(:emit_failure) { |message| said = message }
        handler.instance_variable_set(:@client, client)
        handler.handle
        said
      end

      # feat/search asks the command object to split on '=' for it.
      def command(klass, args)
        arg1, _, arg2 = args.partition('=')
        cmd = double(:args => args, :page => 1)
        allow(cmd).to receive(:parse_args).and_return(double(:arg1 => arg1, :arg2 => arg2))

        handler = klass.new(double, cmd, double)
        handler.parse_args
        handler
      end

      it "should send 'feat <old name>' to the feat it became" do
        expect(failure_from(command(PF2FeatDisplayOneCmd, "Aasimar's Mercy"))).to include 'Celestial Mercy'
      end

      it "should send 'feat/search name=<old name>' to the feat it became" do
        expect(failure_from(command(PF2FeatSearchCmd, "name=Aasimar's Mercy"))).to include 'Celestial Mercy'
      end

      it "should leave a genuine empty search saying so, without inventing a rename" do
        expect(failure_from(command(PF2FeatSearchCmd, 'name=Xyzzy'))).to include 'feats'
      end
    end
  end

  module Pf2emagic
    describe "a spell search that finds nothing" do

      before(:each) do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_spells')
          .and_return({ 'Force Barrage' => { 'traits' => [] } })
        allow(Global).to receive(:read_config).with('pf2e_renames', 'spells')
          .and_return({ 'Magic Missile' => { 'status' => 'renamed', 'to' => 'Force Barrage' } })
      end

      it "should send 'spell/search name=<old name>' to the spell it became" do
        said = nil
        client = double
        allow(client).to receive(:emit_failure) { |message| said = message }

        handler = PF2SearchSpellCmd.new(double, double(:args => 'name=Magic Missile', :page => 1), double)
        handler.parse_args
        handler.instance_variable_set(:@client, client)
        handler.handle

        expect(said).to include 'Force Barrage'
      end
    end
  end
end
