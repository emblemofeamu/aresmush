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

      def advancement
        adv = @char.pf2_advancement

        list = []

        adv.each_pair do |key, value|
          # Process according to the data type of the key.
          heading = key.gsub("charclass", "class").split("_").map {|word| word.capitalize}.join(" ")

          if value.is_a? Array
            list << "#{item_color}#{heading}:%xn #{format_open_list(value)}" unless value.empty?
          elsif value.is_a? Hash
            sublist = []
            value.each_pair do |subkey, subvalue|
              subheading = subkey.to_s
                .gsub("charclass", "class")
                .gsub("spells_per_day", "spell_slots_per_day")
                .gsub("addrepertoire", "repertoire")
                .split(/[_\s]+/)
                .map {|word| word.capitalize}
                .join(" ")
              if subvalue.is_a? Array
                sublist << "%r%b%b#{item_color}#{subheading}:%xn #{format_open_list(subvalue)}"
              elsif subvalue.is_a? Hash
                subsublist = []
                subvalue.each_pair do |subsubkey, subsubvalue|
                  subsubheading = format_spell_level_heading(subsubkey)
                    .to_s
                    .split(/[_\s]+/)
                    .map {|word| word.capitalize}
                    .join(" ")
                  if subsubvalue.is_a? Hash
                    # Go one level deeper for nested hashes
                    subsubsublist = []
                    subsubvalue.each_pair do |subsubsubkey, subsubsubvalue|
                      subsubsubheading = format_spell_level_heading(subsubsubkey)
                        .to_s
                        .gsub("_", " ")
                        .split
                        .map {|word| word.capitalize}
                        .join(" ")

                      if subsubsubvalue.is_a? Hash
                        # Display the properties of this hash
                        final_list = []
                        subsubsubvalue.each_pair do |final_key, final_value|
                          final_heading = final_key.to_s.gsub("_", " ").split.map {|word| word.capitalize}.join(" ")
                          formatted_value = final_value.is_a?(String) ? final_value.titleize : final_value
                          final_list << "%r%b%b%b%b%b%b%b%b%xh#{final_heading}:%xn #{formatted_value}"
                        end
                        subsubsublist << "%r%b%b%b%b%b%b%xh#{subsubsubheading}:%xn#{final_list.join}"
                      else
                        subsubsublist << "%r%b%b%b%b%b%b%xh#{subsubsubheading}:%xn #{subsubsubvalue}"
                      end
                    end
                    subsublist << "%r%b%b%b%b%xh#{subsubheading}:%xn#{subsubsublist.join}"
                  else
                    formatted = subsubvalue.is_a?(Array) ? format_open_list(subsubvalue) : subsubvalue
                    subsublist << "%r%b%b%b%b%xh#{subsubheading}:%xn #{formatted}"
                  end
                end

                sublist << "%r%b%b#{item_color}#{subheading}:%xn #{subsublist.join}"
              else
                sublist << "%r%b%b#{item_color}#{subheading}:%xn #{subvalue}"
              end
            end

            list << "#{item_color}#{heading}:%xn #{sublist.join}"
          else
            list << "#{item_color}#{heading}:%xn #{value}"
          end
        end

        list

      end

      def has_options
        !@to_assign.empty?
      end

      def options
        list = []

        @to_assign.each_pair do |key, value|
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
                       .split("_")
                       .map {|word| word.capitalize}
                       .join(" ")

          if value.is_a? Array
            list << "#{item_color}#{heading}:%xn #{format_open_list(value)}" unless value.empty?
          elsif value.is_a? Hash
            if key == "class option" || key == "charclass option"
              list << "#{item_color}Class Feature Option:%xn"

              value.each_pair do |subkey, subvalue|
                option_list = subvalue.is_a?(Hash) ? subvalue.keys : Array(subvalue)
                list << "%b%b#{item_color}#{subkey}:%xn #{option_list.sort.join(", ")}" unless option_list.empty?
              end

              next
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
                display_subheading = subheading == "General" ? "General feat" : subheading == "Ancestry" ? "Ancestry feat" : subheading
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

        list
      end

      def messages
        msg = Pf2e.advancement_messages(@char)

        return msg.join("%r") if msg
        return t('pf2e.advance_no_messages')
      end

      def help_instructions
        advance_help = t('pf2e.advance_help')
        advance_review_help = t('pf2e.advance_review_help')
        return "%xc#{advance_help}%xn%r%xc#{advance_review_help}%xn"
      end

      def format_open_list(value)
        return value.sort.join(", ") if !value.is_a?(Array) || value.empty?

        open_count = value.count { |item| item.to_s.downcase == 'open' }
        items = value.reject { |item| item.to_s.downcase == 'open' }.sort
        return "#{open_count} open" if items.empty?
        return items.join(", ") if open_count.zero?

        "#{items.join(", ")}, #{open_count} open"
      end

      def format_spell_level_heading(key)
        label = key.to_s.strip

        return "Cantrip" if label.casecmp?("cantrip") || label == "0"
        return "1st-level" if label == "1"
        return "2nd-level" if label == "2"
        return "3rd-level" if label == "3"
        return "4th-level" if label == "4"
        return "5th-level" if label == "5"
        return "6th-level" if label == "6"
        return "7th-level" if label == "7"
        return "8th-level" if label == "8"
        return "9th-level" if label == "9"
        return "10th-level" if label == "10"

        label
      end

    end
  end
end
