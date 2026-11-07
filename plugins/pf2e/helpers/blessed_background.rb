module AresMUSH
  module Pf2e

    # Brings a character who took the Blessed background before it granted anything onto what it grants
    # now. The background is house-ruled to give Guidance as a divine innate cantrip, with no other
    # blessing in its place, so the "Blessed" special ability that stood for the GM's pick is gone.
    #
    # The innate grant goes on the magic object, which is where chargen puts a heritage's or a
    # background's innate spell; the ledger does not record innate spells. The special is taken off
    # through the ledger, whose `add_special` grant is what the next fold writes `pf2_special` from, and
    # then off the attribute itself, for a character still in chargen whose fields are the draft.
    #
    # One character at a time, or `migrate_all!` from tinker. Running it again changes nothing.
    module BlessedBackground

      BACKGROUND = 'Blessed'.freeze

      # The grant the background's config gives, without the name list.
      def self.grant
        stats = Global.read_config('pf2e_background', BACKGROUND, 'magic_stats') || {}
        stats['innate_spell'] || {}
      end

      # How many things it changed: one for the spell, one for each special removed.
      def self.migrate!(char)
        return 0 unless (char.pf2_base_info || {})['background'].to_s == BACKGROUND

        changed = add_innate!(char)
        changed += Ledger.revert_matching!(char, 'add_special', { 'special' => BACKGROUND },
                                           :by => 'Blessed background grants Guidance')

        live = Character[char.id]
        held = Array(live.pf2_special)
        kept = held.reject { |s| s.to_s.casecmp?(BACKGROUND) }

        if kept.size < held.size
          live.update(:pf2_special => kept)
          changed += 1
        end

        changed
      end

      # Every character, saying which it could not move and why: one bad row does not stop the rest.
      def self.migrate_all!(characters: Character.all)
        characters.each_with_object({ 'changed' => {}, 'refused' => {} }) do |char, out|
          count = migrate!(char)
          out['changed'][char.name] = count if count.positive?
        rescue StandardError => e
          out['refused'][char.name] = e.message
        end
      end

      # A character with no magic object has not reached the chargen step that makes one, and gets the
      # spell there. One who already has this grant - the same spell, tradition and ability - is left be.
      def self.add_innate!(char)
        magic = char.magic
        spell = grant
        name = spell['name'].to_s

        return 0 if !magic || name.empty?

        held = Pf2emagic::Entries.innate_for(magic, name).any? do |g|
          g['tradition'].to_s.casecmp?(spell['tradition'].to_s) && g['cast_stat'].to_s.casecmp?(spell['cast_stat'].to_s)
        end

        return 0 if held

        magic.update(:innate_spells => Array(magic.innate_spells) + [ spell.dup ])
        1
      end
    end
  end
end
