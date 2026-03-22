module AresMUSH
  module Pf2e

    # Handles merging the current character data with any pending advancement choices during advancement to allow other choices to be made, as per pen and paper.

    def self.preview_repertoire(char, class_key = nil)
      magic = char.magic
      repertoire = Marshal.load(Marshal.dump(magic&.repertoire || {}))

      advancement = char.pf2_advancement || {}
      pending_rep = advancement['repertoire'] || {}
      return repertoire unless pending_rep.is_a?(Hash) && !pending_rep.empty?

      target_class = class_key || char.pf2_base_info['charclass']

      if pending_rep.keys.any? { |k| !Pf2e.level_key?(k) }
        pending_rep = pending_rep[target_class] || {}
      end

      return repertoire unless pending_rep.is_a?(Hash) && !pending_rep.empty?

      class_rep = repertoire[target_class] || {}

      pending_rep.each_pair do |level, spells|
        existing = Array(class_rep[level])
        additions = Array(spells).reject { |s| s.to_s.strip.empty? || s.to_s.downcase == 'open' }
        class_rep[level] = (existing + additions).uniq
      end

      repertoire[target_class] = class_rep
      repertoire
    end

    def self.preview_skill_prof(char, skill_name)
      current_prof = Pf2eSkills.get_skill_prof(char, skill_name)
      progression = Global.read_config('pf2e', 'prof_progression') || []
      return current_prof if progression.empty?

      advancement = char.pf2_advancement || {}
      pending = []
      pending += Array(advancement['raise skill'])
      pending += Array(advancement['raise skill choice'])

      normalized = pending.select { |s| !s.to_s.strip.empty? && s.to_s.downcase != 'open' }
                          .map { |s| s.to_s.downcase }

      raise_count = normalized.count(skill_name.to_s.downcase)
      return current_prof if raise_count.zero?

      index = progression.index(current_prof) || 0
      target_index = [index + raise_count, progression.length - 1].min

      progression[target_index]
    end

    def self.preview_spellbook(char, class_key = nil)
      magic = char.magic
      spellbook = Marshal.load(Marshal.dump(magic&.spellbook || {}))

      advancement = char.pf2_advancement || {}
      pending_book = advancement['spellbook'] || {}
      return spellbook unless pending_book.is_a?(Hash) || pending_book.is_a?(Array)

      target_class = class_key || char.pf2_base_info['charclass']

      if pending_book.is_a?(Hash) && pending_book.keys.any? { |k| !Pf2e.level_key?(k) }
        pending_book = pending_book[target_class] || {}
      end

      return spellbook if pending_book.nil? || pending_book == {}

      class_book = spellbook[target_class] || {}

      if pending_book.is_a?(Hash)
        pending_book.each_pair do |level, spells|
          existing = Array(class_book[level])
          additions = Array(spells).reject { |s| s.to_s.strip.empty? || s.to_s.downcase == 'open' }
          class_book[level] = (existing + additions).uniq
        end
      else
        Array(pending_book).each do |spell|
          next if spell.to_s.strip.empty? || spell.to_s.downcase == 'open'
          sp = Pf2emagic.get_spell_details(spell)
          spdeets = sp && sp[1]
          next unless spdeets

          level_key = spdeets['base_level'].to_s
          existing = Array(class_book[level_key])
          class_book[level_key] = (existing + [spell]).uniq
        end
      end

      spellbook[target_class] = class_book
      spellbook
    end

    def self.preview_feat_names(char)
      current = char.pf2_feats.values.flatten.map { |f| f.to_s.upcase }

      advancement = char.pf2_advancement || {}
      pending_feats = advancement['feats'] || {}

      pending = pending_feats.values.flatten
                          .map { |f| f.to_s.upcase }
                          .reject { |f| f.empty? || f == 'OPEN' }

      (current + pending).uniq
    end

    def self.preview_magic_tradition(char)
      magic = char.magic
      base = Marshal.load(Marshal.dump(magic&.tradition || {}))
      advancement = char.pf2_advancement || {}
      pending = advancement['magic_stats'] || {}
      return base if pending.empty?

      pending.each_pair do |class_key, stats|
        next unless stats.is_a?(Hash)
        next unless stats['tradition'].is_a?(Hash)
        next if stats['tradition'].empty?

        trad, prof = stats['tradition'].first
        base[class_key] = [trad.to_s.downcase, prof]
      end

      base
    end

  end
end