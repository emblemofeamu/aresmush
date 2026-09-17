module AresMUSH
  module Pf2e

    class PF2AdvanceSpellCmd
      include CommandHandler
      prepend Pf2e::RecordsDraftStep

      attr_accessor :type, :level, :value, :old_value, :magic_class

      def parse_args
        return unless cmd.args

        parts = cmd.args.split("=", 2)
        left = parts[0]
        right = parts[1]

        left_parts = left.split("/").map { |p| trim_arg(p) }
        list_type = left_parts[0]

        if left_parts.size >= 3
          self.type = downcase_arg(list_type)
          self.magic_class = titlecase_arg(left_parts[1])
          self.level = trim_arg(left_parts[2])
        else
          self.type = downcase_arg(list_type)
          self.magic_class = nil
          self.level = trim_arg(left_parts[1])
        end

        spells = trimmed_list_arg(right, "/")

        if spells
          if spells[1]
            self.value = spells[1]
            self.old_value = spells[0]
          else
            self.value = spells[0]
          end
        end

      end

      def required_args
        [ self.type, self.level, self.value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        to_assign = enactor.pf2_to_assign
        charclass = enactor.pf2_base_info['charclass']
        level = self.level.to_i.zero? ? 'cantrip' : self.level

        # Where the pick lands: whose list, the entries in it, and the rank they live under.
        found = Pf2e::Advancement::SpellSlots.resolve(Pf2e::CharState.of(enactor),
          :type => self.type, :rank => level, :magic_class => self.magic_class, :charclass => charclass)

        return if Pf2e::CharState.emit_error!(client, found)

        # Only a spellbook has entries reserved at a rank, so only a spellbook can be full while
        # something is still open, and the restriction lookup is worth doing only then.
        found = Pf2e::Advancement::SpellSlots.spend_from_pool(found.state,
          :full => self.type == 'spellbook' && rank_full?(found.state, level, charclass),
          :rank => level,
          :max_rank => Pf2e.preview_max_spell_rank(enactor, charclass))

        return if Pf2e::CharState.emit_error!(client, found)

        class_key = found.state['class_key']
        entries = found.state['entries']
        list = found.state['list']
        list_key = found.state['list_key']
        spent_from_pool = found.state['from_pool']

        return take_innate(level, list, entries, class_key) if self.type == "innate"

        entry = Pf2e::Advancement::SpellSlots.entry_to_fill(list, self.old_value, self.type)

        return if Pf2e::CharState.emit_error!(client, entry)

        old = entry.state['token']
        class_for_spell = class_key || charclass

        choice = with_previewed_tradition(class_for_spell) do
          Pf2emagic.check_spell(enactor, class_for_spell, level, self.value, true)
        end

        if choice.is_a? String
          client.emit_failure choice
          return
        end

        spell = choice[0]

        # The rules a spell pick has to satisfy, from the one place chargen asks them too.
        failure = Pf2emagic::SpellPick.check(
          'list' => self.type,
          'rank' => level,
          'spell' => spell,
          'tradition' => Pf2emagic::Entries.tradition_of(enactor.magic, class_for_spell),
          'details' => choice[1] || {},
          'adapted' => Pf2emagic.adapted_spell?(enactor, class_for_spell, spell),
          'picks' => list,
          'known' => known_for(class_for_spell))

        return if Pf2e::CharState.emit_error!(client, failure)

        advancement = enactor.pf2_advancement

        # Spending the slot and recording the spell, as slot deltas. This was four branches:
        # one per list shape, each doubled for whether the lists are keyed by class. The shape
        # differences are now in the path, and the path is worked out once.
        deltas = if spent_from_pool
          # An any-rank slot pays, and the spell lands under the rank it actually is.
          [ Slots.consume(spell_path(class_key, list_key)), Slots.add(spell_path(class_key, level), [ spell ]) ]
        else
          # `old` is 'open' for a new pick, or the spell being replaced - the same fill either
          # way, told which entry it is allowed to spend.
          [ Slots.fill(spell_path(class_key, list_key), spell, :tokens => [ old ]) ]
        end

        updated = Slots.apply(to_assign, deltas)

        return if Pf2e::CharState.emit_error!(client, updated)

        # The draft mirrors the pool for this list, which is what advance/done reads.
        mirror = [ self.type, class_key ].compact
        Slots.write(advancement, mirror, Slots.read(updated, mirror))

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = updated

        enactor.save

        client.emit_success t('pf2e.add_ok', :item => spell, :list => self.type)
      end

      # A level that grants a new spellcasting source does not grant it until `advance/done`, so a
      # spell picked for it during the level has no tradition to be measured against yet. The
      # tradition the level will grant stands in for the duration of the check, on the in-memory
      # magic object only - nothing here saves it, and the ensure puts it back whatever happens.
      #
      # The player types the source's name, and every other name in the game is matched
      # case-insensitively - so both lookups here are too. Matching exactly missed the preview for
      # `advance/spell repertoire/oracle archetype/...` against a draft holding `Oracle Archetype`,
      # which left the source with no tradition and refused every spell as one the class cannot cast.
      def with_previewed_tradition(class_for_spell)
        magic = enactor.magic

        return yield unless class_for_spell && magic
        return yield if magic.tradition.keys.any? { |key| key.to_s.casecmp?(class_for_spell.to_s) }

        previews = Pf2e.preview_magic_tradition(enactor) || {}
        source = previews.keys.find { |key| key.to_s.casecmp?(class_for_spell.to_s) }

        return yield unless source && previews[source]

        magic.tradition = magic.tradition.merge(source => previews[source])

        begin
          yield
        ensure
          magic.tradition = magic.tradition.reject { |key, _| key.to_s.casecmp?(source.to_s) }
        end
      end

      # An innate grant is recorded twice while the level is open: as the pending entry in the
      # draft's magic_stats, which is what advance/done hands to the magic object, and as a slot in
      # the pool, which is what the review screen counts. Neither is a spellcasting entry yet, so
      # the prepared and spontaneous path below does not apply.
      def take_innate(level, list, entries, class_key)
        return client.emit_failure t('pf2emagic.innate_no_new_spells') unless list.is_a?(Array)

        result = resolve_innate_spell(level, self.value, list, class_key)

        return client.emit_failure result if result.is_a?(String)

        spell = result[0]

        update_innate_advancement(spell, list, entries, level, class_key)

        client.emit_success t('pf2e.add_ok', :item => spell, :list => 'innate spells')
      end

      # What the character already knows for this class, counting the picks this level has staged.
      # Which list that is follows from what is being added: a signature spell is designated from
      # the repertoire, so it asks the repertoire.
      def known_for(class_key)
        preview = self.type == 'spellbook' ? Pf2e.preview_spellbook(enactor, class_key) : Pf2e.preview_repertoire(enactor, class_key)

        preview[class_key] || {}
      end

      # Where a spell list lives in the pool.
      #
      # Three shapes, one path. A spellbook may be a flat list or one list per rank; repertoire and
      # signature are always per rank; and a character casting from more than one class has all of
      # them keyed by class first. Which applies is the path, not the logic.
      def spell_path(class_key, rank)
        [ self.type, class_key, rank ].compact
      end

      # What the rule needs that only the magic object knows: how many entries the rank reserves,
      # and which spells may sit in them.
      def rank_full?(found, level, charclass)
        for_class = found['class_key'] || charclass
        restriction = Pf2emagic.advancement_restriction_at(enactor, for_class, level)

        return Pf2e::Advancement::SpellSlots.rank_full?(found['list'], self.value, 0, []) unless restriction

        eligible = Pf2emagic.restricted_spell_list(enactor, for_class, restriction['name'], level)

        Pf2e::Advancement::SpellSlots.rank_full?(found['list'], self.value, restriction['count'], eligible)
      end

      def innate_stats(advancement, class_key)
      # magic_stats is either a flat block of stats or one keyed by the source that granted them (a
      # class, an archetype, or a feat), so the pending innate entry is looked up both ways. The hash
      # is returned rather than a copy so callers can record a choice on it in place.
        magic_stats = advancement['magic_stats']

        return nil if !magic_stats.is_a?(Hash)
        return magic_stats['innate_spell'] if magic_stats['innate_spell'].is_a?(Hash)

        source = if class_key
          magic_stats.keys.find { |k| k.to_s.casecmp?(class_key.to_s) }
        else
          magic_stats.keys.find { |k| magic_stats[k].is_a?(Hash) && magic_stats[k]['innate_spell'].is_a?(Hash) }
        end

        return nil if !source

        stats = magic_stats[source]

        stats.is_a?(Hash) ? stats['innate_spell'] : nil
      end

      def resolve_innate_spell(level, value, list, class_key=nil)
        advancement = enactor.pf2_advancement || {}
        pending = innate_stats(advancement, class_key)

        return t('pf2emagic.innate_no_new_spells') unless pending

        names = Array(pending['name'])

        if self.old_value
          return t('pf2emagic.innate_spell_to_delete_not_found') unless names.any? { |n| n.to_s.casecmp?(self.old_value) }
        else
          return t('pf2emagic.innate_no_new_spells') unless names.any? { |n| n.to_s.downcase == 'open' }
        end

        open_slot = list.index "open"
        old = if open_slot
          "open"
        elsif self.old_value
          list.select { |s| s.to_s.downcase.match? self.old_value.downcase }.first
        else
          nil
        end

        return t('pf2emagic.innate_spell_to_delete_not_found') unless old

        hash = Pf2emagic.find_common_spells
        match = hash.keys.select { |s| s.downcase == value.downcase }

        return t('pf2emagic.innate_no_such_spell') if match.empty?
        return t('pf2emagic.innate_multiple_matches', :item => 'spell') if (match.size > 1)

        to_add = match.first
        return t('pf2emagic.innate_spell_already_on_list_to_assign') if list.any? { |s| s.to_s.casecmp?(to_add) }

        deets = hash[to_add]

        failure = Pf2emagic::SpellPick.check_innate(
          'rank' => level,
          'details' => deets,
          'tradition' => pending['tradition'],
          'granted_rank' => pending['level'])

        return t(failure.key, **Pf2e::CharState.symbolize(failure.args)) if failure

        [ to_add ]
      end

      # `entries` is the rank-keyed hash this list lives in, so the rank's slots go back into the
      # pool under the same key the resolution found them under.
      def update_innate_advancement(spell, list, entries, level, class_key=nil)
        advancement = enactor.pf2_advancement || {}
        pending = innate_stats(advancement, class_key)

        return unless pending

        names = Array(pending['name'])
        replace_index = if self.old_value
          names.index { |n| n.to_s.casecmp?(self.old_value) }
        else
          names.index { |n| n.to_s.downcase == 'open' }
        end

        return unless replace_index

        # Recorded on the pending entry itself, which is part of the advancement hash saved below.
        names[replace_index] = spell
        pending['name'] = names.size == 1 ? names.first : names

        open_slot = list.index("open")
        open_slot = list.index { |s| s.to_s.casecmp?(self.old_value) } if open_slot.nil? && self.old_value

        if open_slot
          list.delete_at open_slot
          list << spell
        end

        entries[level] = list

        to_assign = enactor.pf2_to_assign

        if class_key
          to_assign[self.type] ||= {}
          to_assign[self.type][class_key] = entries
        else
          to_assign[self.type] = entries
        end

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save
      end
    end
  end
end
