module AresMUSH
  module Pf2emagic

    def self.is_caster?(char)
      magic = char.magic
      return false unless magic
      return false if magic.tradition.empty?
      return true
    end

    def self.generate_spells_today(char)

      magic = char.magic

      return t('pf2emagic.not_caster') unless magic

      pclass = magic.spells_prepared.keys.map { |c| c.downcase }

      sclass = magic.repertoire.keys.map { |c| c.downcase }

      class_list = (pclass + sclass).uniq

      class_list.each do |cc|
        case cc
        when "wizard", "druid", "cleric", "witch"
          prepared_list = magic.spells_prepared

          magic.update(spells_today: prepared_list)
        when "bard", "oracle", "sorcerer"
          spells_today = generate_blank_spell_list(magic)

          magic.update(spells_today: spells_today)
        else
          return nil
        end
      end

    end

    def self.do_refocus(target, enactor)

      # This is included because it validates the existence of a magic object.
      return t('pf2emagic.not_caster') unless is_caster?(target)

      magic, focus_pool = target.magic, magic.focus_pool

      current, max = focus_pool["current"], focus_pool["max"]

      # Max focus pool defaults to zero and is always 1-3 if target has a focus pool.
      return t('pf2emagic.no_focus_pool') if max.zero?

      # These checks are skipped if an admin is force-refocusing the target.
      if !enactor.is_admin?
        return t('pf2emagic.cant_refresh_pool') unless current.zero?

        last_refocus, current_time = magic.last_refocus, Time.now

        # Last refocus can be nil, use 0 epoch if it is

        last_refocus = Time.at(0) unless last_refocus

        elapsed = (current_time - last_refocus).to_i

        return t('pf2emagic.cant_refresh_time') unless (elapsed > 3600)
      end

      current = max

      focus_pool["current"] = current
      magic.update(focus_pool: focus_pool)
      magic.update(last_refocus: Time.now)

      return nil
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
      all_feats = char.pf2_feats.values.flatten.uniq

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

  end
end
