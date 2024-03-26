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
          client.emit_failure t('pf2e.bad_option', :element => selected_element, :options => options.join(", "))
          return
        elsif selected_option.is_a? Array
          if selected_option.empty?
            client.emit_failure t('pf2e.bad_option', :element => selected_element, :options => options.join(", "))
            return
          elsif selected_option.size > 1
            client.emit_failure t('pf2e.multiple_matches', :element => self.element)
            return
          else
            selected_option = selected_option.first
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
          elsif selected_element == "specialize"
            base_info['specialize_info'] = ""
          end

          enactor.update(pf2_base_info: base_info)
        when "deity", "alignment"
          info = enactor.pf2_faith
          info[selected_element] = selected_option

          enactor.update(pf2_faith: info)
        end

        client.emit_success t('pf2e.option_set', :element => selected_element, :option => selected_option)

      end

    end

  end
end
