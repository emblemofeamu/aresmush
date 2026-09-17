module AresMUSH
  module Pf2emagic

    ANY_RANK = 'any'

    def self.any_rank?(key)
      key.to_s.casecmp?(ANY_RANK)
    end

    def self.adapted_spell?(char, charclass, spell_name)
      magic = char.magic
      return false unless magic

      entry = (magic.adapted_spells || {}).find { |name, _| name.to_s.casecmp?(spell_name.to_s) }
      return false unless entry

      klass = entry[1].is_a?(Hash) ? entry[1]['class'].to_s : ''

      klass.empty? || klass.casecmp?(charclass.to_s)
    end

    def self.is_caster?(char)
      magic = char.magic
      return false unless magic

      trad = magic.tradition
      trad = trad.delete('innate')
      innate_only = trad.empty?

      return false if innate_only && !Entries.innate?(magic)
      return true
    end

    def self.generate_spells_today(char)

      magic = char.magic

      spells_today = {}

      return t('pf2emagic.not_caster') unless magic

      class_list = magic.tradition.keys
      class_list.delete('innate')

      class_list.each do |cc|
        caster_type = Pf2emagic.get_caster_type(cc)
        next unless caster_type

        if caster_type == 'prepared'
          prepared_list = magic.spells_prepared
          spells_today[cc] = prepared_list[cc] || {}
        else
          spells_today[cc] = Entries.slots(magic, cc)
        end
      end

      # Only the ranked ones take a daily use; cantrips are cast at will.
      innate_spells_today = Entries.innate_ranked(magic).each_with_object({}) do |grant, today|
        rank = grant['level'].to_s

        today[rank] = Array(today[rank]) + [ grant['name'] ]
      end

      spells_today['innate'] = innate_spells_today unless innate_spells_today.empty?

      magic.update(spells_today: spells_today)

    end

    def self.do_refocus(target, enactor)

      # This is included because it validates the existence of a magic object.
      return t('pf2emagic.not_caster') unless is_caster?(target)

      magic = target.magic
      focus_pool = magic.focus_pool

      current = focus_pool["current"].to_i
      max = focus_pool["max"].to_i

      has_focus_magic = Entries.focus?(magic)

      if max.zero?
        recalculated_max = get_max_focus_pool(target, 0)
        recalculated_max = 1 if recalculated_max.zero? && has_focus_magic

        if recalculated_max.zero?
          return t('pf2emagic.no_focus_pool')
        end

        max = recalculated_max
        current = [ current, max ].min

        focus_pool["max"] = max
        focus_pool["current"] = current
        magic.update(focus_pool: focus_pool)
      end

      # Max focus pool defaults to zero and is always 1-3 if target has a focus pool.
      return t('pf2emagic.no_focus_pool') if max.zero?

      # These checks are skipped if an admin is force-refocusing the target.
      if !enactor.is_admin?
        return t('pf2emagic.cant_refocus_pool') unless current < max

        last_refocus, current_time = magic.last_refocus, Time.now

        # Last refocus can be nil, use 0 epoch if it is

        last_refocus = Time.at(0) unless last_refocus

        elapsed = (current_time - last_refocus).to_i

        local_last_refocus = OOCTime.localtime(enactor, last_refocus)
        formatted_last_refocus = local_last_refocus.strftime("%-l:%M%P")

        return t('pf2emagic.cant_refocus_time', :time => formatted_last_refocus) unless (elapsed > 3600)
      end

      spent = (max - current).to_i
      charclass_feats = Array(Pf2e::DraftSheet.of(target).feats_by_bucket['charclass']).map { |f| f.to_s.upcase }
      charclass_features = Array(target.pf2_features['charclass_features']).map { |f| f.to_s.upcase }
      charclass = target.pf2_base_info['charclass']

      two_point_refocus_feats = [
        'DOMAIN FOCUS',
        'INSPIRATIONAL FOCUS',
        'PRIMAL FOCUS',
        'MEDITATIVE FOCUS',
        "WARDEN'S FOCUS",
        'BLOODLINE FOCUS',
        'HEX FOCUS',
        'BONDED FOCUS'
      ]

      three_point_refocus_feats = [
        'DOMAIN WELLSPRING',
        'PRIMAL WELLSPRING',
        'MEDITATIVE WELLSPRING',
        "WARDEN'S WELLSPRING",
        'BLOODLINE WELLSPRING',
        'HEX WELLSPRING'
      ]

      has_two_point_feat = !(charclass_feats & two_point_refocus_feats).empty?
      has_three_point_feat = !(charclass_feats & three_point_refocus_feats).empty?

      is_oracle = (charclass == 'Oracle')
      has_major_curse = is_oracle && charclass_features.include?('MAJOR CURSE')
      has_extreme_curse = is_oracle && charclass_features.include?('EXTREME CURSE')

      restore_points = 1
      if spent >= 3 && (has_three_point_feat || has_extreme_curse)
        restore_points = 3
      elsif spent >= 2 && (has_two_point_feat || has_major_curse)
        restore_points = 2
      end

      current = [ current + restore_points, max ].min

      focus_pool["current"] = current
      magic.update(focus_pool: focus_pool)
      magic.update(last_refocus: Time.now)

      return nil
    end

    def self.curriculum_spells(char, charclass, level)
      specialize = char.pf2_base_info['specialize']
      return [] if specialize.blank?

      specialty = Global.read_config('pf2e_specialty', charclass.to_s, specialize)
      return [] unless specialty.is_a?(Hash)

      curriculum = specialty['curriculum']
      return [] unless curriculum.is_a?(Hash)

      key = curriculum.keys.find { |k| k.to_s.casecmp?(level.to_s) }

      Array(key && curriculum[key]).compact.map(&:to_s)
    end

    def self.apply_stat_delta(current, value)
      return value unless value.is_a?(String) && value.strip.match?(/\A[+-]\d+\z/)

      current.to_i + value.strip.to_i
    end

    def self.get_max_focus_pool(char, change)
      magic = char.magic

      return 0 unless magic

      # Calculate all the focus pool points that the character could have available.
      # From character class

      mstat_class = Global.read_config('pf2e_class', char.pf2_base_info['charclass'], 'chargen')['magic_stats']

      if mstat_class
        fp_from_charclass = mstat_class['focus_pool'] ? mstat_class['focus_pool'] : 0
      else
        fp_from_charclass = 0
      end

      # From feats
      all_feats = Pf2e::DraftSheet.of(char).feats_by_bucket.values.flatten.uniq

      values = []

      all_feats.each do |feat|
        details = Pf2e.get_feat_details(feat)
        (values << 0 && next) if details.is_a? String

        mstats = details[1]['magic_stats']
        (values << 0 && next) unless mstats

        feat_fp = mstats['focus_pool']
        (values << 0 && next) unless feat_fp

        values << feat_fp
      end

      fp_from_feats = values.sum

      (fp_from_charclass + fp_from_feats + change).clamp(0,3)
    end

    def self.get_spell_details(term)
      result = get_spells_by_name(term)

      return t('pf2emagic.no_match', :item => "spells") if result.empty?
      return t('pf2e.multiple_matches', :element => 'spell') if result.size > 1

      spell_name = result.first

      spell_details = Global.read_config('pf2e_spells', spell_name)

      [ spell_name, spell_details ]
    end

    # Every spell a source casting `tradition` could put in a slot of `rank`.
    #
    # The same two rules SpellPick enforces when a pick is made - the tradition has to match, and a
    # spell cannot be learned above its own rank or in the wrong kind of slot - asked in advance,
    # so a player can read the list instead of guessing a name and being refused.
    def self.eligible_spells(tradition, rank)
      wanted = tradition.to_s.downcase
      cantrip_slot = rank.to_s.casecmp?('cantrip') || rank.to_s.to_i.zero?

      (Global.read_config('pf2e_spells') || {}).select do |_name, details|
        traditions = Array(details['tradition']).compact.map { |trad| trad.to_s.downcase }

        next false unless traditions.include?(wanted)

        base = details['base_level']
        spell_cantrip = base.to_s.casecmp?('cantrip') || base.to_s.to_i.zero?

        next spell_cantrip if cantrip_slot
        next false if spell_cantrip

        base.to_i <= rank.to_i
      end.keys.sort
    end

    def self.search_spells(search_type, term, operator='=')
      spell_info = Global.read_config('pf2e_spells')

      case search_type
      when 'name'
        match = spell_info.select { |k,v| k.upcase.match? term.upcase }
      when 'traits'
        match = spell_info.select { |k,v| v['traits'].include? term.downcase }
      when 'level'
        # Invalid operator defaults to ==.
        case operator
        when '<'
          match = spell_info.select { |k,v| (v['base_level'].to_i < term.to_i) && v['tradition'] }
        when '>'
          match = spell_info.select { |k,v| (v['base_level'].to_i > term.to_i) && v['tradition'] }
        else
          match = spell_info.select { |k,v| (v['base_level'].to_i == term.to_i) && v['tradition'] }
        end
      when 'tradition'
        match = spell_info.select { |k,v| v['tradition'] && (v['tradition'].include? term.downcase) }
      when 'school'
        match = spell_info.select { |k,v| v['school']&.include?(term.capitalize) }
      when 'bloodline'
        match = spell_info.select { |k,v| v['bloodline']&.include?(term.downcase) }
      when 'cast'
        match = spell_info.select { |k,v| v['cast']&.include? term.downcase }
      when 'description', 'desc', 'effect'
        match = spell_info.select { |k,v| v['effect'].upcase.match? term.upcase }
      end

      match.keys

    end

    def self.sort_level_spell_list(spells)
      # This function takes a hash and sorts it by integer-converted key.
      spells.sort {|a,b| a.first.to_i <=> b.first.to_i}.to_h
    end

    # The display name for a spell rank, the same everywhere a rank is shown regardless of the
    # caster's class.
    def self.rank_label(level)
      return 'Cantrip' if level.to_s.strip.casecmp?('cantrip') || level.to_i.zero?

      n = level.to_i
      suffix = case n % 10
               when 1 then 'st'
               when 2 then 'nd'
               when 3 then 'rd'
               else 'th'
               end

      "#{n}#{suffix}-rank"
    end

  end
end
