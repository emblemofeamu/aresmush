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

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when "damage"
        return PF2DamagePlayerCmd
      when "sheet"
        case cmd.switch
        when "show"
          return PF2ShowSheetCmd
        when "combat"
          return PF2DisplayCombatSheetCmd
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
          return PF2AwardXPCmd
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
      when "encounter", "initiative", "init"
        case cmd.switch
        when "start"
          return PF2InitiateCombatCmd
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
        when "scan"
          return PF2EncounterScanCmd
        when "end"
          return PF2EncounterEndCmd
        when "restart"
          return PF2EncounterRestartCmd
        when "bonus", "penalty"
          return PF2EncounterBonusPenaltyCmd
        when "expire"
          return PF2EncounterExpireBonusesCmd
        when "remove"
          return PF2EncounterRemoveCmd
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
      when "refresh"
        return PF2ForceRefreshCmd
      when "rest"
        return PF2DailyPrepCmd
      when "formulas"
        case cmd.switch
        when "add"
          return PF2FormulaAddCmd
        when "remove"
          return PF2FormulaRemoveCmd
        when nil
          return PF2DisplayFormulasCmd
        end
      when "autorest"
        return PF2AutoDailyPrepCmd
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

    def self.get_web_request_handler(request)
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
      end

      nil
    end

  end
end
