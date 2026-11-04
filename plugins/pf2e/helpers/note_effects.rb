module AresMUSH
  module Pf2e

    # A roll's notes, and the effects they link. Foundry shows a note in the chat card with a link to an
    # effect, Sympathetic Strike's on a hit, and the player drags it onto whoever it is for. Here the note
    # is told, and each effect it links is put on whoever `pf2e_note_effects.yml` says, or offered as the
    # `effect/add` that would.
    #
    # One put on carries where it came from: the note's item, who rolled, and the outcome, which is what
    # Sympathetic Strike's effect reads (`parent:context:check:outcome`) to take -1 on a hit and -2 on a
    # critical hit.
    module NoteEffects
      def self.table
        Global.read_config('pf2e_note_effects') || {}
      end

      # `notes` as `Check#notes` and `Rules.notes` answer them. `degree` is the roll's, and nil where there
      # was none to speak of. `done` names effects the roll has already put on someone, which a note
      # linking the same one leaves alone.
      def self.tell(scene, notes, out, degree: nil, done: [])
        notes.each do |note|
          Acting.note_once(out, note['text']) unless note['text'].to_s.empty?

          Array(note['effects']).each do |name|
            next if Array(done).include?(name)

            whom = applied_to(scene, name, note, degree)

            whom ? put_on(scene, whom, name, note, degree, out) : offer(scene, name, out)
          end
        end
      end

      # Who the engine puts this on, or nil where it is offered: only for an effect the table applies,
      # from a note that named the outcome the roll came to.
      def self.applied_to(scene, name, note, degree)
        entry = table[name] || {}

        return nil unless entry['apply'] && degree && Array(note['outcome']).any?

        entry['for'].to_s == 'self' ? scene.actor : scene.target
      end

      def self.put_on(scene, whom, name, note, degree, out)
        origin = ActiveEffects.origin(item: { 'name' => note['source'] }, by: scene.actor.holder, outcome: degree)
        applied = ActiveEffects.apply(whom.holder, name, :applied_by => scene.actor.label, :encounter => scene.encounter,
                                                         :origin => origin)

        return out['lines'] << Acting.told(applied.key, applied.args) if applied.err?

        out['lines'] << Acting.told('pf2e.act_now_under', :target => whom.label, :effect => applied.state.name,
                                                       :lasts => ActiveEffects.remaining(applied.state))
      end

      def self.offer(scene, name, out)
        entry = table[name] || {}
        whom = entry['for'].to_s == 'self' ? scene.actor : scene.target
        who = whom ? whom.label : '<who>'
        line = Acting.told('pf2e.act_note_effect', :effect => name, :command => "effect/add #{who}=#{name}")

        out['lines'] << line unless out['lines'].include?(line)
      end
    end
  end
end
