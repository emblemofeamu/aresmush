require "plugin_test_loader"

module AresMUSH
  module Pf2e
    module Advancement

      # What a feat does to the pool of things still to pick, asked directly. Before this was
      # data, the only way to find out was to run the command and inspect the character.
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

          it "should open two cantrips for a spontaneous caster" do
            details = skill_feat('grants' => { 'cantrip_expansion' => true })
            deltas = FeatSlots.deltas('Cantrip Expansion', details, :bucket => 'charclass', :spontaneous => true)

            opened = deltas.find { |d| d[:op] == 'open' }

            expect(opened[:count]).to eq 2
            expect(opened[:path]).to eq [ 'repertoire', 'cantrip' ]
          end

          # A prepared caster gets Cantrip Expansion's effect through their spellbook instead,
          # so there is no repertoire slot to open.
          it "should open nothing for a prepared caster" do
            details = skill_feat('grants' => { 'cantrip_expansion' => true })
            deltas = FeatSlots.deltas('Cantrip Expansion', details, :bucket => 'charclass', :spontaneous => false)

            expect(deltas.map { |d| d[:op] }).to eq %w(fill)
          end

          it "should put the cantrips where a multi-class caster keeps them" do
            details = skill_feat('grants' => { 'cantrip_expansion' => true })
            deltas = FeatSlots.deltas('Cantrip Expansion', details,
              :spontaneous => true, :cantrip_path => [ 'repertoire', 'Sorcerer', 'cantrip' ])

            expect(deltas.first[:path]).to eq [ 'repertoire', 'Sorcerer', 'cantrip' ]
          end
        end

        describe :openings do
          it "should say what taking the feat opens up" do
            details = skill_feat('grants' => { 'cantrip_expansion' => true })
            opened = FeatSlots.openings('Cantrip Expansion', details,
              :bucket => 'charclass', :spontaneous => true, :opens_choice => true)

            expect(opened).to eq('feat choice/Cantrip Expansion' => 1, 'repertoire/cantrip' => 2)
          end

          it "should say nothing opens when nothing does" do
            expect(FeatSlots.openings('Assurance', skill_feat, :bucket => 'skill')).to eq({})
          end
        end

        # The deltas are the whole description, so applying them to a pool is the pick.
        describe "applied to a pool" do
          it "should fill the slot and open what the feat brings, in one fold" do
            details = skill_feat('grants' => { 'cantrip_expansion' => true })
            pool = { 'feats' => { 'charclass' => [ 'open' ] } }

            deltas = FeatSlots.deltas('Cantrip Expansion', details,
              :bucket => 'charclass', :spontaneous => true, :opens_choice => true)

            result = Slots.apply(pool, deltas)

            expect(result['feats']['charclass']).to eq [ 'Cantrip Expansion' ]
            expect(result['feat choice']['Cantrip Expansion']).to eq [ 'open' ]
            expect(result['repertoire']['cantrip']).to eq %w(open open)
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
