require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      # What a feat does to the pool of things still to pick, asked directly of the data rather than
      # by running the command and inspecting the character.
      describe FeatSlots do

        def skill_feat(extra = {})
          { 'feat_type' => [ 'Skill' ] }.merge(extra)
        end

        describe :deltas do
          it "should spend the slot it was asked to fill" do
            deltas = FeatSlots.deltas('Assurance', skill_feat, :bucket => 'skill')

            expect(deltas.size).to eq 1
            expect(deltas.first[:op]).to eq 'fill'
            expect(deltas.first[:path]).to eq [ 'feats', 'skill' ]
            expect(deltas.first[:value]).to eq 'Assurance'
          end

          # A feat granted outright by an archetype is not spending anything.
          it "should spend nothing when no bucket is given" do
            expect(FeatSlots.deltas('Assurance', skill_feat)).to eq []
          end

          it "should open the feat's own choice when this taking opens one" do
            deltas = FeatSlots.deltas('Additional Lore', skill_feat, :bucket => 'skill', :opens_choice => true)

            expect(deltas.map { |d| d[:op] }).to eq %w(fill open)
            expect(deltas.last[:path]).to eq [ 'feat choice', 'Additional Lore' ]
          end

          it "should not open a choice on a taking that does not have one" do
            deltas = FeatSlots.deltas('Additional Lore', skill_feat, :bucket => 'skill', :opens_choice => false)

            expect(deltas.map { |d| d[:op] }).to eq %w(fill)
          end

          # Extra cantrips reach a caster through a magic_stats block, which every feat that grants
          # them uses, so there is no slot rule for them here.
          it "should leave magic a feat grants to the magic_stats path" do
            details = skill_feat('magic_stats' => { 'spontaneous' => { 'repertoire' => { 'cantrip' => 2 } } })

            expect(FeatSlots.deltas('Cantrip Expansion', details, :bucket => 'charclass').map { |d| d[:op] }).to eq %w(fill)
          end
        end

        describe :openings do
          it "should say what taking the feat opens up" do
            opened = FeatSlots.openings('Additional Lore', skill_feat,
              :bucket => 'skill', :opens_choice => true)

            expect(opened).to eq('feat choice/Additional Lore' => 1)
          end

          it "should say nothing opens when nothing does" do
            expect(FeatSlots.openings('Assurance', skill_feat, :bucket => 'skill')).to eq({})
          end
        end

        # The deltas are the whole description, so applying them to a pool is the pick.
        describe "applied to a pool" do
          it "should fill the slot and open what the feat brings, in one fold" do
            pool = { 'feats' => { 'skill' => [ 'open' ] } }

            deltas = FeatSlots.deltas('Additional Lore', skill_feat,
              :bucket => 'skill', :opens_choice => true)

            result = Slots.apply(pool, deltas)

            expect(result['feats']['skill']).to eq [ 'Additional Lore' ]
            expect(result['feat choice']['Additional Lore']).to eq [ 'open' ]
          end

          it "should refuse the whole fold when the slot it needs is not open" do
            pool = { 'feats' => { 'charclass' => [ 'Power Attack' ] } }
            result = Slots.apply(pool, FeatSlots.deltas('Sudden Charge', skill_feat, :bucket => 'charclass'))

            expect(result).to be_a Err
            expect(result.code).to eq :no_free
          end
        end
      end
    end
  end
end
