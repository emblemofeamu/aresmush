require "plugin_test_loader"

module AresMUSH

  # Reading a character's sheet rows once for the length of a sweep.
  #
  # find_skill reads the whole skills collection out of Redis on every call. Listing the feats a
  # character is eligible for asks it 584 times, and a level 20 character with a dozen Lores has
  # 255 skill rows - so one `advance/feats charclass` spent 956ms of the single reactor thread
  # re-reading the same rows. Reading them once takes that to a few milliseconds.
  describe Pf2e::SheetReads do

    def skill(name)
      double(:name => name, :name_upcase => name.upcase, :prof_level => 'trained')
    end

    def char_reading(counter, rows)
      char = double(:name => 'Someone')
      allow(char).to receive(:skills) { counter[:reads] += 1; rows }

      char
    end

    it "should find a skill by name" do
      char = char_reading({ :reads => 0 }, [ skill('Occultism'), skill('Arcana') ])

      expect(Pf2eSkills.find_skill('arcana', char).name).to eq 'Arcana'
    end

    it "should answer nil for a skill the character does not have" do
      char = char_reading({ :reads => 0 }, [ skill('Occultism') ])

      expect(Pf2eSkills.find_skill('Arcana', char)).to be_nil
    end

    it "should read the collection once however many lookups a sweep makes" do
      counter = { :reads => 0 }
      char = char_reading(counter, [ skill('Occultism'), skill('Arcana') ])

      Pf2e::SheetReads.holding(char) do
        50.times { Pf2eSkills.find_skill('Arcana', char) }
      end

      expect(counter[:reads]).to eq 1
    end

    it "should still find the right skill through the cache" do
      char = char_reading({ :reads => 0 }, [ skill('Occultism'), skill('Arcana') ])

      found = Pf2e::SheetReads.holding(char) { Pf2eSkills.find_skill('occultism', char) }

      expect(found.name).to eq 'Occultism'
    end

    # Held past the sweep it would go stale the moment a skill was raised, which is exactly what
    # a level-up does straight afterwards.
    it "should read again once the sweep is over" do
      counter = { :reads => 0 }
      char = char_reading(counter, [ skill('Arcana') ])

      Pf2e::SheetReads.holding(char) { Pf2eSkills.find_skill('Arcana', char) }
      Pf2eSkills.find_skill('Arcana', char)

      expect(counter[:reads]).to eq 2
    end

    # Two uncached lookups read twice, which is how this tells "no cache left behind" from
    # "a cache left behind that happens to hold the right rows".
    it "should put the cache back even when the sweep raises" do
      counter = { :reads => 0 }
      char = char_reading(counter, [ skill('Arcana') ])

      expect { Pf2e::SheetReads.holding(char) { raise 'boom' } }.to raise_error('boom')

      2.times { Pf2eSkills.find_skill('Arcana', char) }

      expect(counter[:reads]).to eq 2
    end

    # One character's rows must never answer for another's.
    it "should not answer for a different character" do
      counter = { :reads => 0 }
      cached = char_reading(counter, [ skill('Arcana') ])
      other = double(:name => 'Someone Else')
      allow(other).to receive(:skills).and_return([ skill('Stealth') ])

      inside = Pf2e::SheetReads.holding(cached) { Pf2eSkills.find_skill('Stealth', other) }

      expect(inside.name).to eq 'Stealth'
    end

    # A sweep that asks nothing should cost nothing.
    it "should not read at all when the sweep looks nothing up" do
      counter = { :reads => 0 }
      char = char_reading(counter, [ skill('Arcana') ])

      Pf2e::SheetReads.holding(char) { :nothing_asked }

      expect(counter[:reads]).to eq 0
    end

    # Abilities go through the same memo, and a prerequisite on an attribute is as common as one
    # on a skill.
    it "should read each collection once, not once between them" do
      counter = { :reads => 0 }
      char = char_reading(counter, [ skill('Arcana') ])
      allow(char).to receive(:abilities) { counter[:reads] += 1; [ skill('Strength') ] }

      Pf2e::SheetReads.holding(char) do
        10.times do
          Pf2e::SheetReads.rows(char, :skills)
          Pf2e::SheetReads.rows(char, :abilities)
        end
      end

      expect(counter[:reads]).to eq 2
    end

    it "should return what the sweep returned" do
      char = char_reading({ :reads => 0 }, [ skill('Arcana') ])

      expect(Pf2e::SheetReads.holding(char) { :done }).to eq :done
    end
  end
end
