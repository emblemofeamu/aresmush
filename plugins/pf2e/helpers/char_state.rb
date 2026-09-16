module AresMUSH
  module Pf2e

    # The bridge between a live character and the pure chargen cores.
    #
    # `of` snapshots a character into a plain hash. `build` assembles that hash and is pure,
    # so specs construct a state directly instead of needing a character at all. `commit!`
    # writes a core's Result back: scalar attributes with update, sheet changes through the
    # ledger.
    module CharState

      # Attributes a core may read, mapped to their state key. Anything not listed here is
      # deliberately invisible to the cores.
      def self.of(char, config: ConfigView.live, at_level: nil)
        build({
            'base_info' => char.pf2_base_info,
            'faith' => char.pf2_faith,
            'level' => char.pf2_level,
            'xp' => char.pf2_xp,
            'checkpoint' => char.pf2_checkpoint,
            'baseinfo_locked' => char.pf2_baseinfo_locked,
            'abilities_locked' => char.pf2_abilities_locked,
            'skills_locked' => char.pf2_skills_locked,
            'to_assign' => char.pf2_to_assign,
            'advancement' => char.pf2_advancement,
            'advancing' => char.advancing,
            'archetypes' => char.pf2_archetypeinfo,
            'cg_assigned' => char.pf2_cg_assigned,
            'boosts_working' => char.pf2_boosts_working,
            'boosts' => char.pf2_boosts,
            'lang' => char.pf2_lang,
            'traits' => char.pf2_traits,
            'chargen_stage' => char.chargen_stage,
            'approved' => char.is_approved?,
            'admin' => char.is_admin?,
            'name' => char.name,
            'abilities' => char.abilities.to_a.map { |a| a.name },
            'ability_scores' => char.abilities.to_a.each_with_object({}) { |a, h| h[a.name] = a.base_val },
            'saves' => (char.combat && char.combat.saves) || {},
            'cg_skills' => char.skills.to_a.select { |s| s.cg_skill }.map { |s| s.name }
          },
          :sheet => Ledger.derived(char, :at_level => at_level),
          :config => config
        )
      end

      def self.build(data, sheet: nil, config: nil)
        sheet = sheet || {}

        {
          'name' => data['name'],
          'base_info' => data['base_info'] || {},
          'faith' => data['faith'] || {},
          'level' => (data['level'] || 1).to_i,
          'xp' => (data['xp'] || 0).to_i,
          'checkpoint' => data['checkpoint'] || 'start',
          'chargen_stage' => data['chargen_stage'],
          'approved' => !!data['approved'],
          'admin' => !!data['admin'],
          'locks' => {
            'baseinfo' => !!data['baseinfo_locked'],
            'abilities' => !!data['abilities_locked'],
            'skills' => !!data['skills_locked']
          },
          'to_assign' => data['to_assign'] || {},
          # The advancement draft: what has been picked since `advance` and not yet
          # committed. `advancing` is readable but not writable - see STORED_ATTRS.
          'advancement' => data['advancement'] || {},
          'advancing' => !!data['advancing'],
          'archetypes' => data['archetypes'] || {},
          'cg_assigned' => data['cg_assigned'] || {},
          'boosts_working' => data['boosts_working'] || {},
          'boosts' => data['boosts'] || {},
          'lang' => data['lang'] || [],
          'traits' => data['traits'] || [],
          'abilities' => data['abilities'] || [],
          'ability_scores' => data['ability_scores'] || {},
          'saves' => data['saves'] || {},
          'cg_skills' => data['cg_skills'] || [],
          'sheet' => {
            'level' => sheet['level'] || (data['level'] || 1).to_i,
            'skills' => sheet['skills'] || {},
            'lores' => sheet['lores'] || {},
            'feats' => sheet['feats'] || {},
            'features' => sheet['features'] || {},
            'boosts' => sheet['boosts'] || {},
            'languages' => sheet['languages'] || [],
            'spell_access' => sheet['spell_access'] || []
          },
          'config' => config || ConfigView.live
        }
      end

      # State keys that are genuinely stored on the character. Everything else on the sheet
      # - feats, features, languages, traits, specials, boosts, xp - is owned by the ledger
      # and written by the materialiser, so a transformation must express those as grants. A
      # core that tried to set them directly would be overwritten by the next fold.
      # `advancing` is deliberately absent: starting and finishing an advancement are commit
      # boundaries, and a core that could flip the flag mid-transformation would change where
      # its own grants land. The shell sets it, either side of the core.
      STORED_ATTRS = {
        'base_info' => 'pf2_base_info',
        'faith' => 'pf2_faith',
        'checkpoint' => 'pf2_checkpoint',
        'to_assign' => 'pf2_to_assign',
        'advancement' => 'pf2_advancement',
        'archetypes' => 'pf2_archetypeinfo',
        'cg_assigned' => 'pf2_cg_assigned',
        'boosts_working' => 'pf2_boosts_working',
        'chargen_stage' => 'chargen_stage'
      }.freeze

      LOCK_ATTRS = {
        'baseinfo' => 'pf2_baseinfo_locked',
        'abilities' => 'pf2_abilities_locked',
        'skills' => 'pf2_skills_locked'
      }.freeze

      # The character attributes a transformation actually changed. Pure, so the decision
      # about what to persist is itself testable.
      def self.diff_attrs(before, after)
        attrs = {}

        STORED_ATTRS.each_pair do |key, attr|
          attrs[attr] = after[key] if before[key] != after[key]
        end

        LOCK_ATTRS.each_pair do |key, attr|
          before_lock = (before['locks'] || {})[key]
          after_lock = (after['locks'] || {})[key]
          attrs[attr] = after_lock if before_lock != after_lock
        end

        attrs
      end

      # Applies a successful outcome: the attributes it moved, then its grants as one ledger
      # transaction. Returns the attrs written, so a caller can log or assert on them.
      def self.commit!(char, before, outcome, source_type: 'chargen', source_ref: nil, effective_level: nil, granted_by: nil)
        return {} if outcome.err?

        attrs = diff_attrs(before, outcome.state)

        attrs.each_pair { |attr, value| char.update(attr.to_sym => value) }

        # While a draft is open - chargen before approval, or an advancement before
        # advance/done - what a transformation grants is applied straight to the working copy,
        # and taking it back edits the working copy too. Grants become history only at the
        # matching commit boundary, which is what gives them the right level and source: a
        # language picked during a level-up belongs to that level_up transaction, not to a
        # transaction of its own written the moment the player typed it.
        if Ledger.drafting?(char)
          Ledger.apply_draft!(char, outcome.grants)
          Ledger.undo_draft!(char, outcome.revocations)

          return attrs
        end

        # Revocations first: taking a pick back before re-granting keeps the two from
        # cancelling each other out when a transformation does both.
        outcome.revocations.each do |revocation|
          Ledger.revert_matching!(char, revocation['kind'], revocation['match'] || {}, :by => "#{source_type}-undo-#{Time.now.to_i}")
        end

        if !outcome.grants.empty?
          Ledger.write(char, :source_type => source_type, :source_ref => source_ref, :effective_level => effective_level, :granted_by => granted_by) do |txn|
            outcome.grants.each do |g|
              overrides = {}
              overrides['effective_level'] = g['effective_level'] if g.key?('effective_level')
              overrides['source_ref'] = g['source_ref'] if g.key?('source_ref')
              txn.grant(g['kind'], g['payload'] || {}, overrides)
            end
          end
        end

        Ledger.materialize!(char) if !outcome.revocations.empty? && outcome.grants.empty?

        attrs
      end

      # Reports an Err to the player. Returns true when there was an error, so a command
      # reads `return if CharState.emit_error!(client, outcome)`.
      # nil means "no objection", so a guard-style core can return nil or an Err and the
      # shell reads it the same way as a full outcome.
      def self.emit_error!(client, outcome)
        return false if outcome.nil? || outcome.ok?

        client.emit_failure t(outcome.key, **symbolize(outcome.args))
        true
      end

      # Announces an Ok's messages, after the change has been saved.
      def self.emit_messages!(client, outcome)
        return if outcome.err?

        outcome.messages.each do |message|
          args = symbolize(message['args'] || {})

          if message['type'] == 'ooc'
            client.emit_ooc t(message['key'], **args)
          else
            client.emit_success t(message['key'], **args)
          end
        end
      end

      def self.symbolize(args)
        (args || {}).each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end
    end
  end
end
