module AresMUSH
  class Character
    attribute :pf2_baseinfo_locked, :type => DataType::Boolean
    attribute :pf2_abilities_locked, :type => DataType::Boolean
    attribute :pf2_skills_locked, :type => DataType::Boolean
    attribute :pf2_checkpoint, :default => 'start'
    attribute :pf2_reset, :type => DataType::Boolean
    attribute :advancing, :type => DataType::Boolean

    # Used for daily refresh
    attribute :pf2_last_refresh, :type => DataType::Time
    attribute :pf2_auto_refresh, :type => DataType::Boolean

    attribute :pf2_base_info, :type => DataType::Hash, :default => { 'ancestry'=>"", 'heritage'=>"", 'background'=>"", 'charclass'=>"", "specialize"=>"", 'specialize_info'=>""}
    attribute :pf2_level, :type => DataType::Integer, :default => 1
    attribute :pf2_xp, :type => DataType::Integer, :default => 0
    attribute :pf2_advancement, :type => DataType::Hash, :default => {}
    attribute :pf2_conditions, :type => DataType::Hash, :default => {}
    attribute :pf2_features, :type => DataType::Array, :default => []
    attribute :pf2_traits, :type => DataType::Array, :default => []
    attribute :pf2_feats, :type => DataType::Hash, :default => { "ancestry"=>[], "charclass"=>[], "skill"=>[], "general"=>[], "archetype" => [], "dedication" => [] }
    attribute :pf2_faith, :type => DataType::Hash, :default => { 'deity'=>"", 'alignment'=>"" }
    attribute :pf2_special, :type => DataType::Array, :default => []
    attribute :pf2_boosts_working, :type => DataType::Hash, :default => { 'free'=>[], 'ancestry'=>[], 'background'=>[], 'charclass'=> [] }
    attribute :pf2_boosts, :type => DataType::Hash, :default => {}
    attribute :pf2_lang, :type => DataType::Array, :default => []
    attribute :pf2_viewsheet, :type => DataType::Hash, :default => {}
    attribute :pf2_to_assign, :type => DataType::Hash, :default => {}
    attribute :pf2_cg_assigned, :type => DataType::Hash, :default => {}
    attribute :pf2_adv_assigned, :type => DataType::Hash, :default => {}
    attribute :pf2_size, :default => ""
    attribute :pf2_movement, :type => DataType::Hash, :default => {}
    attribute :pf2_roll_aliases, :type => DataType::Hash, :default => {}
    attribute :pf2_actions, :type => DataType::Hash, :default => {}
    attribute :pf2_xp_history, :type => DataType::Array, :default => []
    attribute :pf2_is_dead, :type => DataType::Boolean
    attribute :pf2_known_for, :type => DataType::Array, :default => []
    attribute :pf2_formula_book, :type => DataType::Hash, :default => {}
    attribute :pf2_reagents, :type => DataType::Hash, :default => {}
    attribute :pf2_alloc_reagents, :type => DataType::Integer, :default => 0
    # DEPRECATED please use pf2_xp_history for XP, money is handled in the gear plugin
    attribute :pf2_award_history, :type => DataType::Hash, :default => {}
    attribute :pf2_cnotes, :type => DataType::Hash, :default => {}

    collection :abilities, "AresMUSH::Pf2eAbilities"
    collection :skills, "AresMUSH::Pf2eSkills"
    reference :hp, "AresMUSH::Pf2eHP"
    reference :combat, "AresMUSH::Pf2eCombat"
    reference :magic, "AresMUSH::PF2Magic"
    set :encounters, "AresMUSH::PF2Encounter"

    before_delete :delete_pf2

    def delete_pf2
      self.abilities.each { |a| a.delete } if self.abilities
      self.skills.each { |s| s.delete } if self.skills
      self.hp.delete if self.hp
      self.combat.delete if self.combat
      self.magic.delete if self.magic
      self.encounters.each {|e| e.delete self}
    end

  end
end
