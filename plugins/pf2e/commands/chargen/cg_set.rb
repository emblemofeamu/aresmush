module AresMUSH
  module Pf2e

    class PF2SetChargenCmd
      include CommandHandler

      attr_accessor :element, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)
        self.element = downcase_arg(args.arg1)
        self.value = trim_arg(args.arg2)
      end

      def required_args
        [ self.element, self.value ]
      end

      def check_in_chargen
        if enactor.is_approved? || enactor.chargen_locked || enactor.is_admin?
          return t('pf2e.only_in_chargen')
        elsif enactor.pf2_baseinfo_locked
          return t('pf2e.cg_options_locked')
        elsif enactor.chargen_stage.zero?
          return t('chargen.not_started')
        else
          return nil
        end
      end

      def handle
        chargen_elements = %w{ancestry background charclass heritage specialize deity alignment specialize_info}
        selected_element = chargen_elements.find { |o| o.include?(self.element) }

        base_info = enactor.pf2_base_info

        if !selected_element
          client.emit_failure t('pf2e.bad_element', :invalid => self.element, :options => chargen_elements.join(", "))
          return
        elsif selected_element == "heritage"
          ancestry = base_info['ancestry']

          if ancestry.blank?
            client.emit_failure t('pf2e.ancestry_not_set')
            return nil
          end

          options = Global.read_config('pf2e_ancestry', "#{ancestry}", 'heritages').sort
          selected_option = options.find { |o| o.downcase.include? self.value.downcase }
        elsif selected_element == "specialize"
          charclass = base_info['charclass']

          if charclass.blank?
            client.emit_failure t('pf2e.charclass_not_set')
            return nil
          end

          options = Global.read_config('pf2e_specialty', charclass).keys.sort
          selected_option = options.find { |o| o.downcase.include? self.value.downcase }
          selected_option = options.find { |o| o.downcase.include? self.value.downcase }
        elsif selected_element == "specialize_info"
          charclass = base_info['charclass']
          specialty = base_info['specialize']
          specialty_info = Global.read_config('pf2e_specialty', charclass, specialty)
          specialty_has_info = specialty.blank? ? nil : specialty_info.has_key?('choose')

          if specialty.blank?
            client.emit_failure t('pf2e.specialty_not_set')
            return nil
          elsif !specialty_has_info
            client.emit_failure t('pf2e.specialty_no_info')
            return nil
          end

          options = specialty_info['choose']['options'].keys.sort
          selected_option = options.find { |o| o.downcase.include? self.value.downcase }
        elsif selected_element == "deity"
          options = Global.read_config('pf2e_deities').keys
          selected_option = options.find { |o| o.downcase.include? self.value.downcase }
        elsif selected_element == "alignment"
          options = Global.read_config('pf2e', 'allowed_alignments')
          selected_option = options.find { |o| o.downcase == self.value.downcase }
        elsif selected_element == "charclass"
          options = Global.read_config('pf2e_class').keys
          selected_option = options.find { |o| o.downcase == self.value.downcase }
        else
          file = 'pf2e_' + "#{selected_element}"
          section = Global.read_config(file)
          options = section.keys.sort
          # If the specified term is an exact match, take that first.
          selected_option = options.find { |o| o.downcase == self.value.downcase }

          # If no exact match, return options.
          unless selected_option
            selected_option = options.select { |o| o.downcase.include? self.value.downcase }
          end
        end

        # Selected option might be nil or an empty array.
        if !selected_option
          if selected_element == "background"
            client.emit_failure t('pf2e.cg_bad_background')
          else
            client.emit_failure t('pf2e.bad_option', :element => selected_element, :options => options.join(", "))
          end
          return
        elsif selected_option.is_a? Array
          if selected_option.empty?
            if selected_element == "background"
              client.emit_failure t('pf2e.cg_bad_background')
            else
              client.emit_failure t('pf2e.bad_option', :element => selected_element, :options => options.join(", "))
            end
            return
          elsif selected_option.size > 1
            client.emit_failure t('pf2e.multiple_matches', :element => self.element)
            return
          else
            selected_option = selected_option.first
          end
        end

        if Global.read_config('pf2e', 'use_alignment') &&
           base_info['charclass']&.casecmp?('Champion') &&
           ["specialize", "alignment", "deity"].include?(selected_element)
          champion_specialty = selected_element == "specialize" ? selected_option : base_info['specialize']
          champion_alignment = selected_element == "alignment" ? selected_option : enactor.pf2_faith['alignment']
          champion_deity = selected_element == "deity" ? selected_option : enactor.pf2_faith['deity']

          if !champion_specialty.blank?
            specialty_config = Global.read_config('pf2e_specialty', 'Champion', champion_specialty) || {}
            specialty_allowed = specialty_config['allowed_alignments'] || []

            if !champion_alignment.blank? && !specialty_allowed.include?(champion_alignment)
              client.emit_failure t('pf2e.cg_champion_specialty_alignment_mismatch', :specialty => champion_specialty, :options => specialty_allowed.join(", "))
              return
            end

            if !champion_deity.blank?
              deity_allowed = Global.read_config('pf2e_deities', champion_deity, 'allowed_alignments') || []

              if champion_alignment.blank? && (deity_allowed & specialty_allowed).empty?
                filtered_alignments = deity_allowed - ["N", "CN", "LN"]
                client.emit_failure t('pf2e.cg_champion_specialty_deity_mismatch', :specialty => champion_specialty, :deity => champion_deity, :options => filtered_alignments.join(", "))
                return
              end
            end
          end
        end

        case selected_element
        when "ancestry", "background", "charclass", "heritage", "specialize", "specialize_info"
          base_info[selected_element] = selected_option
          if selected_element == "ancestry"
            base_info['heritage'] = ""
          elsif selected_element == "charclass"
            base_info['specialize'] = ""
            base_info['specialize_info'] = ""
            
            # Add charclass features to pf2_features
            class_config = Global.read_config('pf2e_class', selected_option)
            charclass_features = class_config['chargen']['charclass_feature'] || []
            if charclass_features.any?
              features = enactor.pf2_features
              features['charclass_features'] ||= []
              features['charclass_features'].concat(charclass_features).uniq!
              enactor.pf2_features = features
            end
            
            # Also add specialty features if specialty is already selected
            specialty = base_info['specialize']
            if !specialty.blank?
              specialty_config = Global.read_config('pf2e_specialty', selected_option, specialty)
              specialty_features = specialty_config['chargen']['charclass_feature'] || []
              if specialty_features.any?
                features = enactor.pf2_features
                features['charclass_features'] ||= []
                features['charclass_features'].concat(specialty_features).uniq!
                enactor.pf2_features = features
              end
            end
          elsif selected_element == "specialize"
            base_info['specialize_info'] = ""
          end

          enactor.update(pf2_base_info: base_info)
        when "deity", "alignment"
          if Global.read_config('pf2e', 'use_alignment')
            alignment = selected_element == "alignment" ? selected_option : enactor.pf2_faith['alignment']
            deity = selected_element == "deity" ? selected_option : enactor.pf2_faith['deity']

            if !alignment.blank? && !deity.blank?
              allowed_alignments = Global.read_config('pf2e_deities', deity, 'allowed_alignments') || []

              unless allowed_alignments.include?(alignment)
                client.emit_failure t('pf2e.cg_deity_alignment_mismatch', :deity => deity, :options => allowed_alignments.join(", "))
                return
              end
            end
          end

          info = enactor.pf2_faith
          info[selected_element] = selected_option

          enactor.update(pf2_faith: info)
        end

        client.emit_success t('pf2e.option_set', :element => selected_element, :option => selected_option)

        # Set messages here for helpful basic information about the selected option, if applicable.
        if selected_element == "charclass"
          charclass = selected_option
          specialty_config = Global.read_config('pf2e_specialty', charclass) || {}
          specializations = specialty_config.keys.sort
          if specializations.any?
            client.emit_ooc t('pf2e.cg_charclass_specializations', :class => charclass, :specializations => specializations.join(", "))
          end
        end
        if selected_element == "ancestry"
          ancestry = selected_option
          heritage_config = Global.read_config('pf2e_ancestry', ancestry, 'heritages') || {}
          heritages = heritage_config.sort

          client.emit_ooc t('pf2e.cg_ancestry_heritages', :ancestry => ancestry, :heritages => heritages.join(", "))
        end

        # Set messages here for special cases where we want to prompt the user to make another selection based on what they just chose, as a user-friendly experience.
        if selected_element == "specialize"
          charclass = base_info['charclass']
          specialty_config = Global.read_config('pf2e_specialty', charclass, selected_option) || {}
          specialty_choice = specialty_config['choose'] || {}
          specialty_options = specialty_choice['options'] || {}
          if specialty_options.any?
            client.emit_ooc t('pf2e.cg_specialty_info_required', :specialty => selected_option, :class => charclass, :options => specialty_options.keys.sort.join(", "))
          end
        end
        if selected_element == "specialize_info" &&
           base_info['charclass']&.casecmp?('Wizard') &&
           !selected_option.casecmp?('Universalist')
          client.emit_ooc t('pf2e.cg_wizard_school_spell', :wizard_school => selected_option.downcase)
        end

      end

    end

  end
end
