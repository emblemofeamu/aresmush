module AresMUSH
  module Pf2e

    class PF2AdvanceSwapSpellCmd
      include CommandHandler

      attr_accessor :type, :level, :old_value, :new_value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.type = downcase_arg(args.arg1)
        self.level = trim_arg(args.arg2)

        spells = trimmed_list_arg(args.arg3, "/")
        if spells
          self.old_value = spells[0]
          self.new_value = spells[1]
        end
      end

      def required_args
        [ self.type, self.level, self.old_value, self.new_value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def check_repertoire_only
        return nil if self.type == "repertoire"
        return t('pf2e.swapspell_repertoire_only')
      end

      def check_swap_limit
        advancement = enactor.pf2_advancement || {}
        return t('pf2e.swapspell_limit') if advancement['repertoire_swap']
        return nil
      end

      def handle
        magic = enactor.magic
        unless magic
          client.emit_failure t('pf2emagic.not_caster')
          return
        end

        charclass = enactor.pf2_base_info['charclass']
        caster_type = Pf2emagic.get_caster_type(charclass)
        unless caster_type == "spontaneous"
          client.emit_failure t('pf2e.swapspell_repertoire_only')
          return
        end

        level = self.level.to_i.zero? ? 'cantrip' : self.level
        repertoire = magic.repertoire || {}
        class_rep = repertoire[charclass] || {}
        level_list = Array(class_rep[level])

        old_spell = resolve_spell_name(self.old_value)
        return unless old_spell

        unless level_list.any? { |s| s.to_s.casecmp?(old_spell) }
          client.emit_failure t('pf2emagic.not_in_list')
          return
        end

        locked_spells = granted_repertoire_spells(enactor).map { |s| s.downcase }
        if locked_spells.include?(old_spell.downcase)
          client.emit_failure t('pf2e.swapspell_locked')
          return
        end

        choice = Pf2emagic.check_spell(enactor, charclass, level, self.new_value, true)
        if choice.is_a?(String)
          client.emit_failure choice
          return
        end

        new_spell = choice[0]

        if old_spell.casecmp?(new_spell)
          client.emit_failure t('pf2e.swapspell_same')
          return
        end

        if level_list.any? { |s| s.to_s.casecmp?(new_spell) }
          client.emit_failure t('pf2e.already_has', :item => 'spell')
          return
        end

        index = level_list.index { |s| s.to_s.casecmp?(old_spell) }
        level_list[index] = new_spell

        class_rep[level] = level_list
        repertoire[charclass] = class_rep
        magic.update(repertoire: repertoire)

        advancement = enactor.pf2_advancement || {}
        advancement['repertoire_swap'] = {
          'level' => level,
          'old' => old_spell,
          'new' => new_spell
        }
        enactor.update(pf2_advancement: advancement)

        client.emit_success t('pf2e.swapspell_ok', :old => old_spell, :new => new_spell, :level => level)
      end

      def resolve_spell_name(term)
        matches = Pf2emagic.get_spells_by_name(term)
        if matches.empty?
          client.emit_failure t('pf2emagic.no_such_spell')
          return nil
        end

        if matches.size > 1
          client.emit_failure t('pf2emagic.multiple_matches', :item => 'spell')
          return nil
        end

        matches.first
      end

      def granted_repertoire_spells(char)
        charclass = char.pf2_base_info['charclass']
        specialty = char.pf2_base_info['specialize']

        return [] if charclass.to_s.strip.empty? || specialty.to_s.strip.empty?

        specialty_info = Global.read_config('pf2e_specialty', charclass, specialty) || {}
        spells = []

        addrepertoire_from = lambda do |magic_stats|
          return unless magic_stats
          addrep = magic_stats['addrepertoire']
          return unless addrep

          addrep.each_pair do |level, entries|
            Array(entries).each { |spell| spells << spell }
          end
        end

        addrepertoire_from.call(specialty_info.dig('chargen', 'magic_stats'))

        advance = specialty_info['advance'] || {}
        current_level = char.pf2_level.to_i
        advance.each_pair do |lvl, info|
          next unless lvl.to_i <= current_level
          addrepertoire_from.call(info['magic_stats'])
        end

        spells.compact.map(&:to_s)
      end

    end
  end
end
