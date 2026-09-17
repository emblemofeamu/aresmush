module AresMUSH
  module Pf2emagic

    # A stand-in for a PF2Magic object that Entries can read.
    #
    # A reader that goes through Entries sees a merge of the stored rows and a projection of the
    # legacy hashes, so it needs every attribute the projection reads, plus a character to look
    # rows up against. A mixin rather than a helper module, because `double` only resolves inside
    # an example.
    module MagicStub

      DEFAULTS = {
        :tradition => {},
        :spell_abil => {},
        :spells_per_day => {},
        :spellbook => {},
        :repertoire => {},
        :signature_spells => {},
        :restricted_spellbook => {},
        :innate_spells => [],
        :divine_font => nil,
        :restricted_slots => {}
      }.freeze

      # `character` answers nil so Entries.stored finds no rows: a unit spec is describing what the
      # hashes project to, and a row would be a second source of truth it never set up.
      def magic_stub(fields = {})
        double(DEFAULTS.merge(fields).merge(:character => nil))
      end

      # A caster of one class, with the tradition entry that makes Entries see it at all.
      def caster_stub(charclass, category, fields = {})
        magic_stub({ :tradition => { charclass => [ 'arcane', 'trained' ] } }.merge(fields)).tap do |magic|
          allow(Pf2emagic).to receive(:get_caster_type) do |name|
            name.to_s.casecmp?(charclass.to_s) ? category : nil
          end
        end
      end
    end
  end
end
