module AresMUSH
  module Pf2e
    class Pf2eSheet < Ohm::Model
      include ObjectModel

      attribute :pf2_ancestry
      attribute :pf2_background
      attribute :pf2_heritage
      attribute :pf2_class
      attribute :pf2_level
      attribute :pf2_faith
      attribute :pf2_deity
      attribute :pf2_alignment

      reference :char, "AresMUSH::Character"
    end

  end

  class Character
    reference :pf2sheet, "AresMUSH::Pf2e::Pf2eSheet"
  end
end
