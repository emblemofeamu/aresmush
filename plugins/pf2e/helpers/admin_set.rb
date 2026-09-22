module AresMUSH
  module Pf2e

    # What `admin/set` can correct, one row per keyword.
    #
    # A staff correction is history like anything else on the sheet, so a row returns grants and
    # revocations rather than writing. They are written as a `staff` transaction with no
    # effective level: it applies at every level, no rollback reaches it, and `explain_for` can
    # say who made it.
    #
    # Three kinds of state are not in the fold, and a row says so explicitly. An alignment and a
    # deity live in `faith`, which the shell persists from the state. Focus spells and a divine
    # font live on the magic object, and a row asks for them through `magic_ops` - the one place
    # this module reaches outside the ledger.
    #
    # Each row parses its own value words, because the grammars differ: a rank or a level is the
    # last word so a multi-word name can hold the middle.
    module AdminSet

      RANKS = %w{untrained trained expert master legendary}.freeze
      INSTRUCTIONS = %w{add delete}.freeze
      FOCUS_KINDS = %w{cantrip spell}.freeze

      # The divine fonts, named where the magic plugin keeps them so staff and a player's own dfont
      # command cannot come to disagree about what one is.
      def self.fonts
        Pf2emagic::Entries::FONTS
      end

      TARGETS = {
        'skill' => {
          'syntax' => '<skill name> <proficiency level>',
          'plan' => lambda { |words, state, target| AdminSet.plan_skill(words, state, target) }
        },
        'feature' => {
          'syntax' => '[add|delete] <feature name>',
          'plan' => lambda { |words, state, target| AdminSet.plan_feature(words, state, target) }
        },
        # One row for both keywords: which list a spell lands in follows from the class's casting
        # mode, so the same grant serves a spellbook and a repertoire.
        'spellbook' => {
          'syntax' => '<charclass> [add|delete] <spell name> <spell level>',
          'plan' => lambda { |words, state, target| AdminSet.plan_spell_list(words, state, target) }
        },
        'repertoire' => {
          'syntax' => '<charclass> [add|delete] <spell name> <spell level>',
          'plan' => lambda { |words, state, target| AdminSet.plan_spell_list(words, state, target) }
        },
        'focus' => {
          'syntax' => '[add|delete] <charclass> [cantrip|spell] <spell name>',
          'plan' => lambda { |words, state, target| AdminSet.plan_focus(words, state, target) }
        },
        'ability' => {
          'syntax' => '<ability name> <ability score>',
          'plan' => lambda { |words, state, target| AdminSet.plan_ability(words, state, target) }
        },
        'divine font' => {
          'syntax' => '[heal|harm]',
          'plan' => lambda { |words, state, target| AdminSet.plan_divine_font(words, state, target) }
        },
        'alignment' => {
          'syntax' => '<alignment>',
          'plan' => lambda { |words, state, target| AdminSet.plan_alignment(words, state, target) }
        },
        'deity' => {
          'syntax' => '<deity>',
          'plan' => lambda { |words, state, target| AdminSet.plan_deity(words, state, target) }
        }
      }.freeze

      def self.targets
        TARGETS.keys
      end

      def self.syntax(target)
        row = TARGETS[target.to_s.downcase]

        row && row['syntax']
      end

      def self.plan(state, target, words)
        row = TARGETS[target.to_s.downcase]

        unless row
          return Err.new(:unknown_target, 'pf2e.bad_option',
                         'element' => 'admin/set', 'options' => targets.join(', '))
        end

        words = Array(words).reject { |w| w.to_s.blank? }

        return Err.new(:no_value, 'pf2e.bad_value', 'item' => target.to_s) if words.empty?

        row['plan'].call(words, state, target.to_s.downcase)
      end

      # ----------------------------------------------------------------------------------
      # The rows
      # ----------------------------------------------------------------------------------

      def self.plan_skill(words, state, target)
        return short(target) if words.size < 2

        rank = words.last.to_s.downcase
        name = words[0..-2].join(' ')

        return Err.new(:bad_prof, 'pf2e.bad_value', 'item' => 'proficiency level') unless RANKS.include?(rank)

        configured = Array(state['config'].read('pf2e_skills')&.keys).find { |s| s.casecmp?(name) }

        if configured
          ok(state, configured).with_grant('raise_skill', 'skill' => configured, 'to' => rank)
        elsif Pf2e.lore_skill?(name)
          held = (state['sheet']['lores'] || {}).keys.find { |l| l.casecmp?(name) } || name

          ok(state, held).with_grant('add_lore', 'lore' => held, 'to' => rank)
        else
          Err.new(:bad_skill, 'pf2e.bad_skill', 'name' => name)
        end
      end

      def self.plan_feature(words, state, target)
        return short(target) if words.size < 2

        instruction = words.first.to_s.downcase
        name = words[1..-1].join(' ')

        return bad_instruction unless INSTRUCTIONS.include?(instruction)

        if instruction == 'add'
          ok(state, 'Feature').with_grant('grant_feature', 'bucket' => 'charclass_features', 'feature' => name)
        else
          # Both, because a finalized character's features come from the fold and a drafting one's
          # are only on the character.
          holding = (state['sheet']['features'] || {}).values.flatten + (state['features'] || {}).values.flatten
          held = holding.find { |f| f.to_s.casecmp?(name) }

          return Err.new(:not_in_list, 'pf2e.not_in_list', 'option' => name) unless held

          ok(state, 'Feature').with_revocation('grant_feature', 'feature' => held)
        end
      end

      def self.plan_spell_list(words, state, target)
        return short(target) if words.size < 4

        charclass = words.first
        instruction = words[1].to_s.downcase
        rank = words.last
        name = words[2..-2].join(' ')

        return bad_instruction unless INSTRUCTIONS.include?(instruction)

        caster = caster_entry(charclass, state)

        return Err.new(:use_focus_keyword, 'pf2e.use_focus_keyword') unless caster

        spell = match_spell(name, state)

        return Err.new(:not_unique, 'pf2e.not_unique') unless spell

        source = caster['source']
        # Named for the list the class actually keeps, which is the casting mode's to decide and
        # not the keyword staff happened to type.
        element = caster['mode'] == 'prepared' ? 'Spellbook' : 'Repertoire'

        if instruction == 'add'
          ok(state, element).with_grant('spell_access', 'source' => source, 'rank' => spell_rank(rank), 'spell' => spell)
        else
          ok(state, element).with_revocation('spell_access', 'source' => source, 'spell' => spell)
        end
      end

      def self.plan_focus(words, state, target)
        return short(target) if words.size < 4

        instruction = words.first.to_s.downcase
        charclass = words[1]
        kind = words[2].to_s.downcase
        name = words[3..-1].join(' ')

        return bad_instruction unless INSTRUCTIONS.include?(instruction)
        return Err.new(:bad_focus_kind, 'pf2e.bad_option', 'element' => 'focus spell type', 'options' => FOCUS_KINDS.join(', ')) unless FOCUS_KINDS.include?(kind)

        by_source = state['config'].read('pf2e_magic', 'focus_type_by_source') || {}
        source = by_source.keys.find { |c| c.to_s.casecmp?(charclass.to_s) }

        return Err.new(:bad_charclass, 'pf2e.bad_value', 'item' => 'character class') unless source

        focus_type = by_source[source]
        element = "Focus #{kind}"

        if instruction == 'add'
          with_magic(state, element, 'op' => 'update', 'charclass' => source,
                     'info' => { "focus_#{kind}" => { focus_type => [ name ] } })
        else
          with_magic(state, element, 'op' => 'revoke_focus', 'focus_type' => focus_type,
                     'spell' => name, 'kind' => kind)
        end
      end

      def self.plan_ability(words, state, target)
        return short(target) if words.size < 2

        score = words.last.to_i
        name = words[0..-2].join(' ')
        ability = Array(state['abilities']).find { |a| a.to_s.casecmp?(name) }

        return Err.new(:bad_ability, 'pf2e.bad_ability', 'char' => state['name']) unless ability

        # A score is checked for being a positive number and no further: staff correcting a sheet
        # are allowed to put a character outside what chargen would have produced.
        return Err.new(:bad_score, 'pf2e.bad_value', 'item' => 'ability score') unless score > 0

        ok(state, ability).with_grant('set_ability_score', 'ability' => ability, 'to' => score)
      end

      def self.plan_divine_font(words, state, target)
        font = words.join(' ').downcase

        return Err.new(:bad_font, 'pf2e.bad_option', 'element' => 'divine font', 'options' => fonts.join(', ')) unless fonts.include?(font)

        # The word itself, because every reader of the font compares it against 'heal' or 'harm'.
        with_magic(state, 'Divine font', 'op' => 'update', 'charclass' => 'charclass',
                   'info' => { 'divine_font' => [ font ] })
      end

      def self.plan_alignment(words, state, target)
        allowed = Array(state['config'].read('pf2e', 'allowed_alignments'))
        alignment = alignment_code(words)

        return Err.new(:bad_alignment, 'pf2e.bad_value', 'item' => 'alignment') if alignment.blank? || !allowed.include?(alignment)

        faith = (state['faith'] || {}).merge('alignment' => alignment)

        warn_on_mismatch(ok(state.merge('faith' => faith), 'Alignment'), faith, state)
      end

      def self.plan_deity(words, state, target)
        options = Array(state['config'].read('pf2e_deities')&.keys)
        raw = words.join(' ').strip
        deity = options.find { |o| o.to_s.casecmp?(raw) }

        return Err.new(:bad_deity, 'pf2e.bad_value', 'item' => 'deity') unless deity

        faith = (state['faith'] || {}).merge('deity' => deity)

        warn_on_mismatch(ok(state.merge('faith' => faith), 'Deity'), faith, state)
      end

      # ----------------------------------------------------------------------------------
      # Shared pieces
      # ----------------------------------------------------------------------------------

      # A deity's allowed follower alignments are the deity's rule, so the mismatch is said out
      # of character and the change still stands: which of the two to correct is staff's call.
      def self.warn_on_mismatch(outcome, faith, state)
        deity = faith['deity']
        alignment = faith['alignment']

        return outcome if deity.blank? || alignment.blank?

        allowed = Array(state['config'].read('pf2e_deities', deity, 'allowed_alignments'))

        return outcome if allowed.include?(alignment)

        outcome.with_ooc('pf2e.admin_alignment_deity_warning', 'deity' => deity)
      end

      def self.ok(state, element)
        Ok.new(:state => state).with_message('pf2e.updated_ok', 'element' => element, 'char' => state['name'])
      end

      def self.with_magic(state, element, op)
        ops = Array(state['magic_ops']) + [ op ]

        ok(state.merge('magic_ops' => ops), element)
      end

      # Too few words to parse the grammar the row documents, so the grammar is what to say.
      def self.short(target)
        Err.new(:bad_syntax, 'pf2e.admin_set_syntax', 'element' => target, 'syntax' => syntax(target))
      end

      def self.bad_instruction
        Err.new(:bad_instruction, 'pf2e.bad_instruction')
      end

      # Which casting list holds this class, and the class's own spelling of its name. Nil for a
      # class that casts only focus spells, which keeps no list of known spells to correct.
      CASTER_LISTS = {
        'prepared_casters' => 'prepared',
        'prepared_archetypes' => 'prepared',
        'spontaneous_casters' => 'spontaneous',
        'spontaneous_archetypes' => 'spontaneous'
      }.freeze

      def self.caster_entry(charclass, state)
        CASTER_LISTS.each_pair do |key, mode|
          found = Array(state['config'].read('pf2e_magic', key)).find { |c| c.to_s.casecmp?(charclass.to_s) }

          return { 'source' => found, 'mode' => mode } if found
        end

        nil
      end

      # An exact name wins; otherwise a substring has to pick out exactly one spell.
      def self.match_spell(name, state)
        spells = Array(state['config'].read('pf2e_spells')&.keys)
        exact = spells.find { |s| s.to_s.casecmp?(name) }

        return exact if exact

        partial = spells.select { |s| s.to_s.downcase.include?(name.to_s.downcase) }

        partial.size == 1 ? partial.first : nil
      end

      def self.spell_rank(word)
        word.to_i.zero? ? 'cantrip' : word.to_i.to_s
      end

      # 'CN', 'Chaotic Neutral' and 'neutral' all name an alignment code.
      def self.alignment_code(words)
        raw = Array(words).join(' ').strip

        return nil if raw.blank?

        normalized = raw.upcase.gsub(/\s+/, ' ')

        return 'N' if normalized == 'NEUTRAL' || normalized == 'TRUE NEUTRAL'
        return normalized if normalized.length <= 2 && !normalized.include?(' ')

        words.map { |word| word.to_s[0] }.join.upcase
      end
    end
  end
end
