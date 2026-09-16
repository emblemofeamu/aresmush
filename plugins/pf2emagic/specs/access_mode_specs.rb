require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # How a source decides which spells it may cast.
    #
    # PF2e has two answers. A Wizard acquires spells into a spellbook and a Sorcerer knows a
    # repertoire - both enumerate, and each acquisition happens at a level. A Cleric or Druid has
    # no spellbook at all and prepares from the whole divine or primal list, so there is nothing
    # to enumerate. Reading which from config rather than naming classes in code is what stops a
    # new class, or a new spell, from needing anything special.
    describe "access mode" do

      it "should say a spellbook class enumerates" do
        expect(Entries.enumerated?('Wizard')).to be true
        expect(Entries.access('Wizard')).to eq 'enumerated'
      end

      it "should say a repertoire class enumerates" do
        expect(Entries.enumerated?('Sorcerer')).to be true
        expect(Entries.enumerated?('Bard')).to be true
      end

      # The case that matters: a Cleric prepares from the entire divine list, so enumerating it
      # would mean every new divine spell needed applying to every cleric.
      it "should say a class with neither casts by rule" do
        expect(Entries.enumerated?('Cleric')).to be false
        expect(Entries.access('Cleric')).to eq 'tradition'
      end

      it "should say the same of a Druid" do
        expect(Entries.enumerated?('Druid')).to be false
      end

      it "should cope with a class that does not cast at all" do
        expect(Entries.enumerated?('Fighter')).to be false
      end

      it "should cope with nothing at all" do
        expect(Entries.enumerated?(nil)).to be false
        expect(Entries.enumerated?('')).to be false
      end

      it "should cope with a source the config has never heard of" do
        expect(Entries.enumerated?('Bewildering Nonsense')).to be false
      end

      # An archetype is a source in its own right and decides this for itself - a Wizard
      # Archetype acquires spells, a Cleric Archetype does not.
      it "should read an archetype's own config" do
        expect(Entries.enumerated?('Wizard Archetype')).to be true
        expect(Entries.enumerated?('Cleric Archetype')).to be false
      end

      # Nothing in the code names a class, so a new one is classified by what its config grants.
      it "should classify a class it has never seen from its config alone" do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_class', 'Magus').and_return(
          'chargen' => { 'magic_stats' => { 'spellbook' => { '1' => 2 }, 'spells_per_day' => { '1' => 1 } } }
        )

        expect(Entries.enumerated?('Magus')).to be true
      end

      it "should classify a new full-list caster as casting by rule" do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_class', 'Animist').and_return(
          'chargen' => { 'magic_stats' => { 'spells_per_day' => { '1' => 2 }, 'tradition' => { 'divine' => 'trained' } } }
        )

        expect(Entries.enumerated?('Animist')).to be false
      end

      # A Witch is the awkward one: prepared rather than spontaneous, their spells held by their
      # familiar and learned two a level at any rank they can cast, and their tradition set by
      # their patron rather than by the class. The config models all of that, and the derivation
      # has to agree with it.
      it "should say a Witch enumerates, being prepared rather than spontaneous" do
        expect(Entries.enumerated?('Witch')).to be true
        expect(Pf2emagic.get_caster_type('Witch')).to eq 'prepared'
      end

      # A class whose list arrives only through a specialty. Reading it as casting by rule would
      # grant whole-tradition access.
      it "should look in a class's specialties as well" do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_class', 'Patronised').and_return(
          'chargen' => { 'magic_stats' => { 'spells_per_day' => { '1' => 2 } } }
        )
        allow(Global).to receive(:read_config).with('pf2e_specialty', 'Patronised').and_return(
          'Some Patron' => { 'chargen' => { 'magic_stats' => { 'spellbook' => { '1' => 2 } } } }
        )

        expect(Entries.enumerated?('Patronised')).to be true
      end

      # A class that only gains its enumerated list on the way up, not at chargen.
      it "should look at every level, not only chargen" do
        allow(Global).to receive(:read_config).and_call_original
        allow(Global).to receive(:read_config).with('pf2e_class', 'Latecomer').and_return(
          'chargen' => { 'magic_stats' => { 'spells_per_day' => { '1' => 1 } } },
          'advance' => { 4 => { 'magic_stats' => { 'repertoire' => { '2' => 1 } } } }
        )

        expect(Entries.enumerated?('Latecomer')).to be true
      end
    end
  end
end
