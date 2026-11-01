$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Pf2e

    # Makes a command's work one step of a draft, so a player can take it back.
    #
    #   class PF2SetChargenCmd
    #     include CommandHandler
    #     prepend Pf2e::RecordsDraftStep
    #
    # Prepended, so the journal wraps the command's own `handle` and the command has nothing to
    # call. Every command that can change a drafting character declares itself this way; one that
    # forgets is caught by `DraftJournal.stale?`, which refuses an undo rather than restoring a
    # shape from before a change nobody recorded.
    #
    # It lives in this file because a command prepends it while its class body is being read, and
    # the plugin loader reads this file before the command directories.
    module RecordsDraftStep

      def handle
        subject = journal_subject

        return super unless subject

        DraftJournal.step!(subject, cmd.raw.to_s.split('=').first.to_s.strip) { super }
      end

      # Whose draft this command changes. Their own, unless the command defines `draft_subject` -
      # a staff command changes the character it names, and journaling the staff member's draft
      # instead would record nothing and leave the target's journal behind the character.
      #
      # Asked for by a different name than the command answers to, because a prepended module's
      # method wins over the class's: a default here would shadow the command's own.
      def journal_subject
        respond_to?(:draft_subject, true) ? draft_subject : enactor
      end
    end

    # A paged template's footer: the paginator's "page x of y" bar, and under it the command for
    # the next page closed off by the footer line. The including template sets @paginator, and @cmd
    # when it has one; without a command, or on the last page, it is the plain bar.
    #
    # The closing line is %lf rather than a drawn rule, so a screen reader is sent nothing for it.
    #
    # Here for the same reason as RecordsDraftStep: templates include it while their class body is
    # being read, and pf2egear's are read after this plugin.
    module PagedTemplate

      def page_footer
        footer = @paginator.page_footer
        hint = Pf2e.next_page_hint(@cmd, @paginator)

        hint ? "#{footer}%r#{hint}%r%lf" : footer
      end
    end

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    # For app/review stuff. This plugin should never be disabled in the game though
    def self.is_enabled?
      !Global.plugin_manager.is_disabled?("pf2e")
    end 

    def self.shortcuts
      Global.read_config("pf2e", "shortcuts")
    end

    # Each command and page reads a sheet once between its writes (`SheetReads.during`).
    def self.get_cmd_handler(client, cmd, enactor)
      ReadsOnce.wrapped(cmd_handler(client, cmd, enactor))
    end

    def self.get_web_request_handler(request)
      ReadsOnce.wrapped(web_request_handler(request))
    end

    def self.cmd_handler(client, cmd, enactor)
      case cmd.root
      when "damage"
        return PF2DamagePlayerCmd
      when "sheet"
        case cmd.switch
        when "show"
          return PF2ShowSheetCmd
        when "combat"
          return PF2DisplayCombatSheetCmd
        when "why"
          return PF2StatBreakdownCmd
        when "option", "options"
          return PF2RollOptionCmd
        else
          return PF2DisplaySheetCmd
        end
      when "award"
        case cmd.switch
        when "xp"
          return PF2AwardXPCmd
        when "prp"
          return PF2AwardPRPCmd
        end
      when "selfaward"
        case cmd.switch
        when "xp"
          return PF2SelfAwardXPCmd
        when "gold"
          return PF2SelfAwardGoldCmd
        end
      when "cg"
        case cmd.switch
        when "set"
          return PF2SetChargenCmd
        when "review"
          return PF2ReviewChargenCmd
        when "reset"
          return PF2ResetChargenCmd
        when "restore"
          return PF2RestoreChargenCmd
        when "info"
          return PF2ChargenInfoCmd
        when "feat"
          return PF2FeatSetCmd
        when "option"
          return PF2ChoiceOptionCmd
        when "undo", "redo"
          return PF2DraftUndoCmd
        end
      when "roll"
        case cmd.switch
        when nil, "me"
          return PF2RollCommand
        when "for"
          return PF2RollForCommand
        when "taketen"
          return PF2TakeTenCommand
        when "listalias"
          return PF2ListRollAliasCmd
        when "alias"
          return PF2ChangeRollAliasCmd
        end
      when "rollprefix"
        return PF2RollPrefixCmd
      when "boost"
        case cmd.switch
        when "set"
          return PF2BoostSetCmd
        when "unset"
          return PF2BoostUnsetCmd
        end
      when "skill", "skills"
        case cmd.switch
        when "set"
          return PF2SkillSetCmd
        when "unset"
          return PF2SkillUnSetCmd
        when "lore"
          return PF2LoreGroupListCmd
        when nil
          return PF2SkillListCmd
        end
      when "lang"
        case cmd.switch
        when "set"
          return PF2LanguageSetCmd
        when "info"
          return PF2LanguageInfoCmd
        when "unset"
          return PF2LanguageUnSetCmd
        end
      when "feat"
        case cmd.switch
        when "info"
          return PF2FeatInfoCmd
        when "search"
          return PF2FeatSearchCmd
        when nil
          return PF2FeatDisplayOneCmd
        end
      when "knownfor"
        return PF2KnownForCmd
      when "condition"
        case cmd.switch
        when "set"
          return PF2ConditionSetCmd
        end
      when "effect"
        case cmd.switch
        when "add"
          return PF2EffectAddCmd
        when "remove"
          return PF2EffectRemoveCmd
        when "view"
          return PF2EffectViewCmd
        when "search"
          return PF2EffectSearchCmd
        end
      when "effects"
        return PF2EffectListCmd
      when "action"
        # `action/available/combat` arrives as one switch.
        return PF2ActionAvailableCmd if cmd.switch.to_s.start_with?('available')

        case cmd.switch
        # Using an action is acting: the same command whether or not an encounter is running.
        when "use"
          return PF2EncounterActCmd
        when "search"
          return PF2ActionSearchCmd
        when nil
          return PF2ActionViewCmd
        end
      when "encounter", "initiative", "init", "e"
        # `+e/explore=12` and `+e/start=12` arrive with the `=` in the switch and the number as a page.
        if cmd.switch.to_s.include?('=') && cmd.args.to_s.strip.empty?
          switch, rest = cmd.switch.split('=', 2)
          cmd.switch = switch
          cmd.args = "=#{rest}#{cmd.page}"
          cmd.page = nil
        end

        case cmd.switch
        when "act"
          return PF2EncounterActCmd
        when "strike"
          return PF2EncounterStrikeCmd
        when "reload"
          return PF2EncounterReloadCmd
        when "cast"
          return PF2EncounterCastCmd
        when "as"
          return PF2EncounterAsCmd
        when "why"
          return PF2EncounterWhyCmd
        when "how"
          return PF2EncounterHowCmd
        when "turn"
          return PF2EncounterTurnCmd
        when "cover"
          return PF2EncounterCoverCmd
        when "conceal"
          return PF2EncounterConcealCmd
        when "trust", "untrust"
          return PF2EncounterTrustCmd
        when "creature"
          return PF2EncounterCreatureCmd
        when "bestiary"
          return PF2EncounterBestiaryCmd
        when "enter", "leave"
          return PF2EncounterAuraCmd
        when "option"
          return PF2EncounterOptionCmd
        when "sheet"
          return PF2EncounterSheetCmd
        when "csheet"
          return PF2EncounterCombatSheetCmd
        when "undo", "redo"
          return PF2EncounterUndoCmd
        when "rest"
          return PF2EncounterRestCmd
        when "level"
          return PF2EncounterLevelCmd
        when "focus"
          return PF2EncounterFocusCmd
        when "gear"
          return Pf2egear::PF2EncounterGearCmd
        when "use"
          return Pf2egear::PF2EncounterUseCmd
        when "equip"
          return Pf2egear::PF2EncounterEquipCmd
        when "unequip"
          return Pf2egear::PF2EncounterUnequipCmd
        when "loot"
          return Pf2egear::PF2EncounterLootCmd
        when "alchemy"
          return PF2EncounterAlchemyCmd
        when "owner"
          return PF2EncounterOwnerCmd
        when "award"
          return PF2EncounterAwardCmd
        when "refocus"
          return PF2EncounterRefocusCmd
        when "history"
          return PF2EncounterHistoryCmd
        when "start"
          return PF2InitiateCombatCmd
        when "explore", "start/explore"
          return PF2ExploreCmd
        when "view"
          return PF2InitViewCmd
        when "join"
          return PF2InitJoinCmd
        when "next"
          return PF2EncounterNextCmd
        when "prev"
          return PF2EncounterPrevCmd
        when "mod"
          return PF2InitModCmd
        when "add"
          return PF2EncounterAddCmd
        when "adjust"
          return PF2EncounterAdjustCmd
        when "affliction"
          return PF2EncounterAfflictionCmd
        when "scan"
          return PF2EncounterScanCmd
        when "end"
          return PF2EncounterEndCmd
        when "restart"
          return PF2EncounterRestartCmd
        when "remove"
          return PF2EncounterRemoveCmd
        when "resync"
          return PF2EncounterResyncCmd
        when nil
          return PF2InitiateCombatCmd
        end
      when "admin"
        case cmd.switch
        when "set"
          return PF2AdminSetCmd
        when "reset"
          return PF2AdminResetCmd
        when "respec"
          return PF2AdminRespecCmd
        when "rollback"
          return PF2AdminRollbackCmd
        when "unrollback"
          return PF2AdminRollbackRedoCmd
        end
      when "advance"
        if cmd.switch&.start_with?("language=")
          cmd.args = cmd.switch.split("=", 2)[1]
          cmd.switch = "language"
        end
        case cmd.switch
        when nil
          return PF2ADvancementStartCmd
        when "review"
          return PF2AdvanceReviewCmd
        when "raise"
          return PF2AdvanceRaiseCmd
        when "reset"
          return PF2AdvanceResetCmd
        when "feat"
          return PF2AdvanceFeatCmd
        when "feats"
          return PF2AdvanceFeatsCmd
        when "spell"
          return PF2AdvanceSpellCmd
        when "swapspell"
          return PF2AdvanceSwapSpellCmd
        when "option"
          return PF2ChoiceOptionCmd
        when "info"
          return PF2AdvanceInfoCmd
        when "archetype"
          return PF2AdvanceArchetypeCmd
        when "language"
          return PF2AdvanceLanguageCmd
        when "done"
          return PF2AdvanceFinishCmd
        when "undo", "redo"
          return PF2DraftUndoCmd
        end
      when "listxp"
        return PF2ListXPCmd
      when "creature", "creatures"
        case cmd.switch
        when nil
          return cmd.args.to_s.strip.empty? ? PF2CreatureListCmd : PF2CreatureViewCmd
        when "list"
          return PF2CreatureListCmd
        when "save"
          return PF2CreatureSaveCmd
        when "clone"
          return PF2CreatureCloneCmd
        when "set", "unset"
          return PF2CreatureSetCmd
        when "rename"
          return PF2CreatureRenameCmd
        when "notes"
          return PF2CreatureNotesCmd
        when "describe"
          return PF2CreatureDescribeCmd
        when "share", "unshare"
          return PF2CreatureShareCmd
        when "history"
          return PF2CreatureHistoryCmd
        when "retire", "restore"
          return PF2CreatureRetireCmd
        when "submit", "submitown", "withdraw"
          return PF2CreatureSubmitCmd
        when "public"
          return PF2CreaturePublicCmd
        when "owner"
          return PF2CreatureOwnerCmd
        when "new"
          return PF2CreatureNewCmd
        when "purge"
          return PF2CreaturePurgeCmd
        when "queue"
          return PF2CreatureQueueCmd
        when "check"
          return PF2CreatureCheckCmd
        when "approve", "reject", "unpublish"
          return PF2CreatureReviewCmd
        end
      when "hero"
        case cmd.switch
        when nil
          return PF2HeroViewCmd
        when "award"
          return PF2HeroAwardCmd
        when "reroll", "boost"
          return PF2HeroFortuneCmd
        when "survive"
          return PF2HeroSurviveCmd
        when "buy"
          return PF2HeroBuyCmd
        when "give"
          return PF2HeroGiveCmd
        end
      when "alchemy"
        case cmd.switch
        when "prepare"
          return PF2AlchemyPrepareCmd
        when "clear"
          return PF2AlchemyClearCmd
        when nil
          return PF2AlchemyViewCmd
        end
      when "formula", "formulas"
        case cmd.switch
        when "add"
          return PF2FormulaAddCmd
        when "remove"
          return PF2FormulaRemoveCmd
        when "buy"
          return PF2FormulaBuyCmd
        when nil
          return PF2DisplayFormulasCmd
        end
      when "cnote"
        case cmd.switch
        when "add"
          return PF2AddCnoteCmd
        when "remove"
          return PF2RemoveCnoteCmd
        else
          return PF2ViewOneCnoteCmd
        end
      when "cnotes"
        return PF2ViewAllCnotesCmd
      when "commit"
        return PF2CommitCmd
      when "heal"
        return PF2HealPlayerCmd
      end

      nil
    end

    def self.get_event_handler(event_name)
      case event_name
      when "CharApprovedEvent"
        return CharApprovedHandler
      end

      nil
    end

    def self.web_request_handler(request)
      case request.cmd
      when "pf2CharclassFeats"
        return PF2CharclassFeatsHandler
      when "pf2AncestryFeats"
        return PF2AncestryFeatsHandler
      when "pf2GeneralFeats"
        return PF2GeneralFeatsHandler
      when "pf2SkillFeats"
        return PF2SkillFeatsHandler
      when "pf2DedicationFeats"
        return PF2DedicationFeatsHandler
      when "pf2SceneEncounter"
        return PF2SceneEncounterHandler
      when "pf2Encounter"
        return PF2EncounterHandler
      when "pf2Creatures"
        return PF2CreaturesHandler
      when "pf2Creature"
        return PF2CreatureHandler
      when "pf2CreatureOptions"
        return PF2CreatureOptionsHandler
      when "pf2CreatureSpells"
        return PF2CreatureSpellsHandler
      when "pf2CreatureStart"
        return PF2CreatureStartHandler
      when "pf2CreatureCheck"
        return PF2CreatureCheckHandler
      when "pf2CreatureSave"
        return PF2CreatureSaveHandler
      when "pf2CreatureAct"
        return PF2CreatureActHandler
      when "pf2CreatureQueue"
        return PF2CreatureQueueHandler
      when "pf2CreatureReview"
        return PF2CreatureReviewHandler
      when "pf2Actions"
        return PF2ActionsHandler
      when "pf2LastRoll"
        return PF2LastRollHandler
      end

      nil
    end

  end
end
