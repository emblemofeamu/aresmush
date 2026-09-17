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
        # Do they have one of these to select?

        to_assign = enactor.pf2_to_assign

        charclass = enactor.pf2_base_info['charclass']
        type_option = to_assign[self.type]

        unless type_option
          if self.type == charclass.downcase
            client.emit_failure t('pf2e.adv_spell_wrong_type', :class => charclass)
            return
          end

          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        level = self.level.to_i.zero? ? 'cantrip' : self.level

        class_key = nil
        if type_option.is_a?(Hash) && type_option.keys.any? { |k| !Pf2e.level_key?(k) }
          if self.magic_class
            class_key = type_option.keys.find { |k| k.to_s.casecmp?(self.magic_class) }
            unless class_key
              client.emit_failure t('pf2e.adv_not_an_option')
              return
            end
          else
            class_key = type_option.keys.find { |k| k.to_s.casecmp?(charclass) }
            class_key = type_option.keys.first if class_key.nil? && type_option.keys.size == 1
            if class_key.nil?
              client.emit_failure t('pf2e.adv_not_an_option')
              return
            end
          end

          type_option = type_option[class_key]
        end

        list = if self.type == "spellbook"
          type_option.is_a?(Hash) ? type_option[level] : type_option
        else
          type_option[level]
        end

        # A spellbook may be one flat list rather than one per rank, in which case the rank is
        # not part of where it lives.
        list_key = type_option.is_a?(Hash) ? level : nil
        spent_from_pool = false

        if self.type == "spellbook" && type_option.is_a?(Hash) &&
           spellbook_rank_full_for?(list, level, class_key || charclass)
          pool_key = type_option.keys.find { |k| Pf2emagic.any_rank?(k) }
          pool = pool_key && type_option[pool_key]

          if Array(pool).include?("open")
            msg = any_rank_spend_error(level)

            if msg
              client.emit_failure msg
              return
            end

            list = pool
            list_key = pool_key
            spent_from_pool = true
          end
        end

        unless list
          client.emit_failure t('pf2e.adv_no_spell_slots_level', :type => self.type, :level => level_label(level))
          return
        end

        if self.type == "innate"
          unless list.is_a?(Array)
            client.emit_failure t('pf2emagic.innate_no_new_spells')
            return
          end

          result = resolve_innate_spell(level, self.value, list, class_key)
          if result.is_a?(String)
            client.emit_failure result
            return
          end

          spell = result[0]

          update_innate_advancement(spell, list, type_option, level, class_key)

          client.emit_success t('pf2e.add_ok', :item => spell, :list => 'innate spells')
          return
        end


        # Now we have to figure out if we have an open slot.
        open_slot = list.index "open"

        if open_slot
          old = "open"
        elsif self.old_value
          old = list.select {|s| s.downcase.match? self.old_value.downcase}.first

          unless old
            client.emit_failure t('pf2e.not_in_list', :option => self.old_value)
            return
          end

          open_slot = list.index old
        else
          client.emit_failure t('pf2e.no_free', :element => "#{self.type} slot")
          return
        end

        class_for_spell = class_key || charclass
        magic = enactor.magic
        added_tradition = false

        if magic && class_for_spell && !magic.tradition.key?(class_for_spell)
          preview_tradition = Pf2e.preview_magic_tradition(enactor)
          preview_entry = preview_tradition[class_for_spell]

          if preview_entry
            temp_tradition = magic.tradition.dup
            temp_tradition[class_for_spell] = preview_entry
            magic.tradition = temp_tradition
            added_tradition = true
          end
        end

        choice = Pf2emagic.check_spell(enactor, class_for_spell, level, self.value, true)

        if added_tradition
          magic.tradition = magic.tradition.reject { |k, _| k.to_s.casecmp?(class_for_spell) }
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

      # Keep prepared casters from adding spells to spellbooks higher than what they can actually cast.
      def any_rank_spend_error(level)
        return t('pf2e.adv_any_rank_cantrip') if level.to_s.casecmp?('cantrip')

        charclass = enactor.pf2_base_info['charclass']
        max = Pf2e.preview_max_spell_rank(enactor, charclass)

        return nil if max && level.to_i <= max.to_i

        t('pf2e.adv_any_rank_no_slots', :level => level_label(level))
      end

      def spellbook_rank_full_for?(rank_list, level, charclass)
        opens = Array(rank_list).count { |s| s.to_s.casecmp?('open') }
        return true if opens.zero?

        for_class = Pf2emagic.advancement_restricted_spellbook(enactor, charclass)
        return false unless for_class.is_a?(Hash)

        restriction = nil
        reserved = 0
        for_class.each_pair do |name, by_rank|
          count = Pf2emagic.restricted_count_at_rank(by_rank, level)
          next unless count.positive?

          restriction = name
          reserved = count
        end
        return false if reserved.zero?

        eligible = Pf2emagic.restricted_spell_list(enactor, charclass, restriction, level).map { |s| s.to_s.downcase }
        return false if eligible.include?(self.value.to_s.downcase)

        already_eligible = Array(rank_list).count { |s| eligible.include?(s.to_s.downcase) }

        opens <= [ reserved - already_eligible, 0 ].max
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

      def level_label(level)
        return 'cantrip' if level.to_s.downcase == 'cantrip' || level.to_i.zero?

        abs_level = level.to_i.abs
        suffix = case abs_level % 10
                 when 1 then 'st'
                 when 2 then 'nd'
                 when 3 then 'rd'
                 else 'th'
                 end

        "#{abs_level}#{suffix}-rank"
      end

      def update_innate_advancement(spell, list, type_option, level, class_key=nil)
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

        type_option[level] = list

        to_assign = enactor.pf2_to_assign

        if class_key
          to_assign[self.type] ||= {}
          to_assign[self.type][class_key] = type_option
        else
          to_assign[self.type] = type_option
        end

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save
      end
    end
  end
end
