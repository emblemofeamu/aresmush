module AresMUSH
  module Pf2e

    class PF2AdvanceReviewTemplate < ErbTemplateRenderer
      include CommonTemplateFields

      attr_accessor :char, :client

      def initialize(char, client)
        @char = char
        @client = client

        @to_assign = char.pf2_to_assign

        super File.dirname(__FILE__) + "/advance_review.erb"
      end

      def new_level
        @char.pf2_level + 1
      end

      def section_line(title)
        @client.screen_reader ? title : line_with_text(title)
      end

      def title
        "#{@char.name}: Advancing to Level #{new_level}"
      end

      def has_advancement
        !advancement.empty?
      end

      def advancement
        @advancement_lines ||= build_advancement
      end

      def build_advancement
        adv = prune_open_advancement(@char.pf2_advancement).merge(chosen_assignments)

        list = []

        adv.each_pair do |key, value|
          # Process according to the data type of the key.
          heading = format_stat_heading(key)

          if value.is_a? Array
            list << "#{item_color}#{heading}:%xn #{format_open_list(value)}" unless value.empty?
          elsif value.is_a? Hash
            sublist = []
            value.each_pair do |subkey, subvalue|
              subheading = format_stat_heading(subkey)
              if subvalue.is_a? Array
                sublist << "%r%b%b#{item_color}#{subheading}:%xn #{format_open_list(subvalue)}"
              elsif subkey.to_s == 'innate_spell' && subvalue.is_a?(Hash)
                sublist << "%r%b%b#{item_color}#{subheading}:%xn#{innate_spell_lines(subvalue, 4)}"
              elsif subvalue.is_a? Hash
                subsublist = []
                subvalue.each_pair do |subsubkey, subsubvalue|
                  subsubheading = format_stat_heading(subsubkey)
                  if subsubkey.to_s == 'innate_spell' && subsubvalue.is_a?(Hash)
                    # magic_stats keyed by the granting source (feat, archetype, or class).
                    subsublist << "%r%b%b%b%b%xh#{subsubheading}:%xn#{innate_spell_lines(subsubvalue, 6)}"
                  elsif subsubvalue.is_a? Hash
                    # Go one level deeper for nested hashes
                    subsubsublist = []
                    subsubvalue.each_pair do |subsubsubkey, subsubsubvalue|
                      subsubsubheading = format_stat_heading(subsubsubkey)

                      if subsubsubvalue.is_a? Hash
                        # Display the properties of this hash
                        final_list = []
                        subsubsubvalue.each_pair do |final_key, final_value|
                          final_list << "%r%b%b%b%b%b%b%b%b%xh#{format_stat_heading(final_key)}:%xn #{format_stat_value(final_value)}"
                        end
                        subsubsublist << "%r%b%b%b%b%b%b%xh#{subsubsubheading}:%xn#{final_list.join}"
                      else
                        subsubsublist << "%r%b%b%b%b%b%b%xh#{subsubsubheading}:%xn #{format_stat_value(subsubsubvalue)}"
                      end
                    end
                    subsublist << "%r%b%b%b%b%xh#{subsubheading}:%xn#{subsubsublist.join}"
                  else
                    subsublist << "%r%b%b%b%b%xh#{subsubheading}:%xn #{format_stat_value(subsubvalue)}"
                  end
                end

                sublist << "%r%b%b#{item_color}#{subheading}:%xn #{subsublist.join}"
              else
                sublist << "%r%b%b#{item_color}#{subheading}:%xn #{format_stat_value(subvalue)}"
              end
            end

            list << "#{item_color}#{heading}:%xn #{sublist.join}"
          else
            list << "#{item_color}#{heading}:%xn #{format_stat_value(value)}"
          end
        end

        list

      end

      def has_options
        !options.empty?
      end

      def options
        @option_lines ||= build_options
      end

      def build_options
        list = []

        pending_options.each_pair do |key, value|
          next if key == "signature" || key == "gated_feat_options"

          if key == "grants" && value.is_a?(Hash)
            value.each_pair do |feat, grant_info|
              if grant_info.is_a?(Hash) && grant_info['gated_feat']
                gate = grant_info['gated_feat']
                summary = Pf2e.gated_feat_summary(gate)
                list << "#{item_color}#{feat}:%xn #{summary}"
              else
                list << "#{item_color}#{feat}:%xn #{grant_info}"
              end
            end
            next
          end

          # Process according to the data type of the key.
          heading = key.gsub("charclass", "class feat")
                       .gsub(/(?<!raise )skill/, "skill feat(s)")
                       .gsub("key ability", "key attribute")
                       .split(/[_\s]+/)
                       .map {|word| word.capitalize}
                       .join(" ")

          if value.is_a? Array
            formatted = if key == "archetype key ability"
              format_or_list(value)
            else
              format_open_list(value)
            end

            list << "#{item_color}#{heading}:%xn #{formatted}" unless value.empty?
          elsif value.is_a? Hash
            if key == "class option" || key == "charclass option"
              list << "#{item_color}Class Feature Option:%xn"

              value.each_pair do |subkey, subvalue|
                option_list = if subvalue.is_a?(Hash)
                  subvalue.keys
                else
                  Array(subvalue).map { |opt| opt.is_a?(Array) ? opt.first : opt }
                end
                list << "%b%b#{item_color}#{subkey}:%xn #{option_list.sort.join(", ")}" unless option_list.empty?
              end

              next
            end

            if key == "innate"
              innate_lines = innate_option_lines(value)

              unless innate_lines.empty?
                list.concat(innate_lines)
                next
              end
            end

            sublist = []
            value.each_pair do |subkey, subvalue|
              subheading = subkey.to_s
                .gsub("charclass", "class feat(s)")
                .gsub(/(?<!raise )skill/, "skill feat(s)")
                .split
                .map {|word| word.capitalize}
                .join(" ")
              if subvalue.is_a? Array
                display_subheading = subheading

                if key == "feats"
                  display_subheading = format_feat_type_heading(subkey)
                elsif ["repertoire", "spellbook", "innate"].include?(key)
                  level_heading = format_spell_level_heading(subkey)
                  display_subheading = level_heading.casecmp?("cantrip") ? "Cantrip" : "#{level_heading} spell"
                end

                sublist << "#{item_color}#{display_subheading}:%xn #{format_open_list(subvalue)}"
              elsif subvalue.is_a? Hash
                subsublist = []
                subvalue.each_pair do |subsubkey, subsubvalue|
                  subsubheading = format_spell_level_heading(subsubkey)
                    .to_s
                    .gsub("_", " ")
                    .split
                    .map {|word| word.capitalize}
                    .join(" ")
                  formatted = subsubvalue.is_a?(Array) ? format_open_list(subsubvalue) : subsubvalue
                  subsublist << "%r%b%b%xh#{subsubheading}:%xn #{formatted}"
                end

                sublist << "#{item_color}#{subheading}:%xn #{subsublist.join}"
              else
                sublist << "#{item_color}#{subheading}:%xn #{subvalue}"
              end
            end

            list << sublist.join("%r")
          else
            list << "#{item_color}#{heading}:%xn #{value}"
          end
        end

        list.reject { |item| item.to_s.strip.empty? }
      end

      def pending_options
        @pending_options ||= @to_assign.each_with_object({}) do |(key, value), result|
          pending = pending_option(key, value)

          result[key] = pending unless pending.nil?
        end
      end

      CHOICE_FROM_LIST_KEYS = [ 'raise skill choice', 'archetype key ability' ]

      UNRESOLVED_UNTIL_CLEARED_KEYS = [ 'grants', 'gated_feat_options', 'special feat' ]

      def pending_option(key, value)
        return value if UNRESOLVED_UNTIL_CLEARED_KEYS.include?(key.to_s)

        case key.to_s
        when 'archetype'
          # Assigned along with the dedication feat rather than picked, so it is never an option.
          nil
        when *CHOICE_FROM_LIST_KEYS
          value.is_a?(Array) && !value.empty? ? value : nil
        when 'class option', 'charclass option'
          return value unless value.is_a?(Hash)

          pending = value.reject { |_feature, option| option.is_a?(String) }

          pending.empty? ? nil : pending
        when 'archetype specialty choice'
          return value unless value.is_a?(Hash)

          pending = value.select do |_archetype, entry|
            entry.is_a?(Hash) && open_slot?(entry['choice'])
          end

          pending.empty? ? nil : pending
        else
          keep_open_slots(value)
        end
      end

      def chosen_assignments
        chosen = {}

        archetype = @to_assign['archetype']
        chosen['archetype'] = archetype unless archetype.blank?

        specialty = @to_assign['archetype_specialty']
        chosen['archetype_specialty'] = specialty unless specialty.blank? || open_slot?(specialty)

        specialty_choices = @to_assign['archetype specialty choice']
        if specialty_choices.is_a?(Hash)
          made = specialty_choices.select do |_archetype, entry|
            entry.is_a?(Hash) && !open_slot?(entry['choice'])
          end

          chosen['archetype specialty choice'] = made unless made.empty?
        end

        chosen
      end

      def messages
        msg = Pf2e.advancement_messages(@char)

        return msg.join("%r") if msg
        return t('pf2e.advance_no_messages')
      end

      def help_instructions
        advance_help = t('pf2e.advance_help')
        advance_review_help = t('pf2e.advance_review_help')
        return "#{advance_help}%r#{advance_review_help}"
      end

      def format_open_list(value)
        return value.sort.join(", ") if !value.is_a?(Array) || value.empty?

        counts = {
          'open untrained' => 0,
          'open lore untrained' => 0,
          'open lore' => 0,
          'open' => 0
        }

        items = []
        value.each do |item|
          token = item.to_s.downcase
          if counts.key?(token)
            counts[token] += 1
          else
            items << item
          end
        end

        open_labels = []
        counts.each_pair do |label, count|
          next if count.zero?
          open_labels << "#{count} #{label}"
        end

        items = items.sort
        return open_labels.join(", ") if items.empty?
        return items.join(", ") if open_labels.empty?

        "#{items.join(", ")}, #{open_labels.join(", ")}"
      end

      # Config key names labels.
      STAT_HEADING_LABELS = [
        [ 'charclass', 'class' ],
        [ 'spells per day', 'spell slots per day' ],
        [ 'addrepertoire', 'repertoire' ],
        [ 'addspellbook', 'spellbook' ],
        [ 'weapon prof', 'weapon proficiencies' ],
        [ 'armor prof', 'armor proficiencies' ],
        [ 'spell abil', 'spellcasting attribute modifier' ],
        [ 'cast stat', 'spellcasting attribute modifier' ],
        [ 'key abil', 'key attribute' ],
        [ 'prof', 'proficiency' ]
      ]

      def format_stat_heading(key)
        label = format_spell_level_heading(key).to_s.downcase.gsub("_", " ")

        STAT_HEADING_LABELS.each do |find, replace|
          label = label.gsub(/\b#{find}\b/, replace)
        end

        label.split.map { |word| word.capitalize }.join(" ").gsub("Dcs", "DCs")
      end

      def format_stat_value(value)
        return format_open_list(value) if value.is_a?(Array)
        return value.titleize if value.is_a?(String)

        value
      end

      def format_feat_type_heading(key)
        label = key.to_s.gsub("charclass", "class").gsub("_", " ").strip
        label = "#{label} feat" unless label.downcase.end_with?("feat")

        label.split.map { |word| word.capitalize }.join(" ")
      end

      def open_slot?(value)
        Pf2e.open_skill_token?(value)
      end

      def open_slot_count(value)
        return value.values.sum { |sub| open_slot_count(sub) } if value.is_a?(Hash)
        return value.count { |entry| open_slot?(entry) } if value.is_a?(Array)

        open_slot?(value) ? 1 : 0
      end

      def prune_open_advancement(adv)
        prune_open_class_options(prune_open_slot_lists(prune_open_magic_stats(adv)))
      end

      OPEN_SLOT_KEYS = %w(repertoire spellbook signature innate feats languages)

      def open_slot_key?(key)
        OPEN_SLOT_KEYS.include?(key.to_s) || key.to_s.start_with?("raise ")
      end

      def prune_open_slot_lists(adv)
        pruned = {}

        adv.each_pair do |key, value|
          unless open_slot_key?(key)
            pruned[key] = value
            next
          end

          kept = prune_open_slots(value)

          pruned[key] = kept unless kept.nil?
        end

        pruned
      end

      CLASS_OPTION_ADV_KEY = 'charclass_feature option'

      def prune_open_class_options(adv)
        options = adv[CLASS_OPTION_ADV_KEY]

        return adv unless options.is_a?(Hash)

        chosen = options.select { |_feature, option| option.is_a?(String) }
        pruned = adv.dup

        if chosen.empty?
          pruned.delete(CLASS_OPTION_ADV_KEY)
        else
          pruned[CLASS_OPTION_ADV_KEY] = chosen
        end

        pruned
      end

      def prune_open_slots(value)
        if value.is_a?(Array)
          kept = value.reject { |entry| open_slot?(entry) }

          return kept.empty? ? nil : kept
        end

        if value.is_a?(Hash)
          kept = value.each_with_object({}) do |(key, sub), result|
            pruned = prune_open_slots(sub)

            result[key] = pruned unless pruned.nil?
          end

          return kept.empty? ? nil : kept
        end

        open_slot?(value) ? nil : value
      end

      def keep_open_slots(value)
        if value.is_a?(Array)
          kept = value.select { |entry| open_slot?(entry) }

          return kept.empty? ? nil : kept
        end

        if value.is_a?(Hash)
          kept = value.each_with_object({}) do |(key, sub), result|
            pending = keep_open_slots(sub)

            result[key] = pending unless pending.nil?
          end

          return kept.empty? ? nil : kept
        end

        open_slot?(value) ? value : nil
      end

      def prune_open_magic_stats(adv)
        magic_stats = adv['magic_stats']

        return adv unless magic_stats.is_a?(Hash)

        pruned = if magic_stats['innate_spell'].is_a?(Hash)
          chosen_innate_spell?(magic_stats['innate_spell']) ? magic_stats : drop_innate_spell(magic_stats)
        else
          magic_stats.each_with_object({}) do |(source, stats), result|
            if stats.is_a?(Hash) && stats['innate_spell'].is_a?(Hash) && !chosen_innate_spell?(stats['innate_spell'])
              stats = drop_innate_spell(stats)
            end

            result[source] = stats unless stats.is_a?(Hash) && stats.empty?
          end
        end

        adv = adv.dup

        if pruned.empty?
          adv.delete('magic_stats')
        else
          adv['magic_stats'] = pruned
        end

        adv
      end

      def chosen_innate_spell?(info)
        Array(info['name']).any? { |name| !name.to_s.casecmp?('open') }
      end

      def drop_innate_spell(stats)
        stats.reject { |key, _| key.to_s == 'innate_spell' }
      end

      def pending_innate_spell(source)
        magic_stats = @char.pf2_advancement['magic_stats']

        return nil unless magic_stats.is_a?(Hash)
        return magic_stats['innate_spell'] if magic_stats['innate_spell'].is_a?(Hash)

        entry = magic_stats.keys.find { |k| k.to_s.casecmp?(source.to_s) }
        stats = entry ? magic_stats[entry] : nil

        stats.is_a?(Hash) ? stats['innate_spell'] : nil
      end

      def innate_option_lines(value)
        return [] unless value.is_a?(Hash)

        return [] if value.keys.any? { |k| Pf2e.level_key?(k) }

        lines = []

        value.each_pair do |source, slots|
          pending = pending_innate_spell(source)

          return [] unless pending

          open_count = open_slot_count(slots)
          next if open_count.zero?

          lines << "#{item_color}#{source}:%xn%r%b%b%xhInnate Spell(s):%xn #{open_count} open#{innate_spell_detail_lines(pending, 4)}"
        end

        lines
      end

      def format_or_list(value)
        list = Array(value).compact.map { |entry| entry.to_s.strip }.reject(&:empty?)
        return "" if list.empty?
        return list.first if list.size == 1

        "#{list[0..-2].join(", ")} or #{list[-1]}"
      end

      INNATE_SPELL_FIELDS = [
        ['level', 'Spell Rank'],
        ['tradition', 'Tradition'],
        ['cast_stat', 'Spellcasting Attribute Modifier']
      ]

      def innate_spell_lines(info, indent)
        return "" unless info.is_a?(Hash)

        # Chosen names are left un-titleized; they come from the spell list already correctly cased.
        chosen = Array(info['name']).reject { |n| n.to_s.casecmp?('open') }
        name_line = chosen.any? ? "%r#{"%b" * indent}%xhName:%xn #{chosen.join(", ")}" : ""

        "#{name_line}#{innate_spell_detail_lines(info, indent)}"
      end

      # What the slot is, which describes an open slot and a filled one alike.
      def innate_spell_detail_lines(info, indent)
        return "" unless info.is_a?(Hash)

        pad = "%b" * indent

        lines = INNATE_SPELL_FIELDS.map do |key, label|
          value = info[key]
          next if value.nil?

          formatted = if key == 'level'
            format_spell_level_heading(value)
          else
            Array(value).map { |v| v.to_s.titleize }.join(", ")
          end

          "%r#{pad}%xh#{label}:%xn #{formatted}"
        end

        lines.compact.join
      end

      def format_spell_level_heading(key)
        label = key.to_s.strip

        return "Cantrip" if label.casecmp?("cantrip") || label == "0"
        return "1st-rank" if label == "1"
        return "2nd-rank" if label == "2"
        return "3rd-rank" if label == "3"
        return "4th-rank" if label == "4"
        return "5th-rank" if label == "5"
        return "6th-rank" if label == "6"
        return "7th-rank" if label == "7"
        return "8th-rank" if label == "8"
        return "9th-rank" if label == "9"
        return "10th-rank" if label == "10"

        label
      end

    end
  end
end
