module AresMUSH
  module Pf2e

    INFO_FEAT_SLOT_TYPES = %w(general skill ancestry charclass archetype dedication)

    # Lists at or below this go out as a single line; longer ones get the paginated template.
    INFO_PAGINATE_LIMIT = 20

    # Entries per page once paging kicks in. Two columns, so this is 20 rows.
    INFO_PAGE_SIZE = 40

    # The feat slot types this level still has something open in.
    #
    # `advance/info <type>` lists the feats eligible for one type, but only to a player who already
    # knows the vocabulary. This is how one command can answer "what can I take now" without the
    # player being told the words first. Archetype slots nest a level deeper, keyed by archetype.
    # `<element>=<filter>`, with either half allowed to be missing. The element may itself hold
    # spaces, and only the first `=` separates the two.
    def self.split_info_filter(args)
      element, _, filter = args.to_s.partition('=')
      element = element.strip
      filter = filter.strip

      [ element.empty? ? nil : element, filter.empty? ? nil : filter ]
    end

    def self.open_feat_slot_types(char)
      pool = (char.pf2_to_assign || {})['feats']

      return [] unless pool.is_a?(Hash)

      pool.select { |_type, slots| any_open_slot?(slots) }.keys.sort
    end

    def self.any_open_slot?(slots)
      return slots.values.any? { |sub| any_open_slot?(sub) } if slots.is_a?(Hash)
      return slots.any? { |slot| any_open_slot?(slot) } if slots.is_a?(Array)

      slots.to_s.casecmp?('open')
    end

    def self.info_options(char, element)
      return nil if element.blank?

      # A pending feat choice, by name. This is the Assurance case: the player is told to run 'cg/info Assurance' when they take it, and gets the skills still open to them.
      pending = pending_feat_choices(char)
      key = pending.keys.find { |k| k.to_s.casecmp?(element.to_s) }

      if key
        block = find_choice_block(char, key)
        return nil unless block

        return [ key, choice_options(char, key, block) ]
      end

      # A feat slot type. 'general' and 'general feat' both work.
      type = element.to_s.downcase.strip.sub(/\s+feats?\z/, '')

      if INFO_FEAT_SLOT_TYPES.include?(type)
        return [ t('pf2e.info_feat_title', :type => type.capitalize), get_feat_options(char, type) ]
      end

      nil
    end

    # `filter` narrows the pool by substring before paging. A pool of two hundred lores is six
    # pages, which is barely more use to a player than the refusal that sent them here.
    def self.info_option_display(title, options, page, filter = nil)
      options = Array(options).compact

      return { :error => t('pf2e.info_no_options', :element => title) } if options.empty?

      unless filter.to_s.strip.empty?
        wanted = filter.to_s.strip.downcase
        options = options.select { |option| option.to_s.downcase.include?(wanted) }

        return { :error => t('pf2e.info_no_match', :element => title, :filter => filter.to_s.strip) } if options.empty?
      end

      if options.size <= INFO_PAGINATE_LIMIT
        return { :text => t('pf2e.cg_info', :element => title, :options => options.join(", ")) }
      end

      paginator = Paginator.paginate(options, page, INFO_PAGE_SIZE)

      return { :error => paginator.out_of_bounds_msg } if paginator.out_of_bounds?

      { :text => PF2OptionListTemplate.new(paginator, title).render }
    end

  end
end
