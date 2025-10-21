class AddElevenLabsVoiceIdToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :eleven_labs_voice_id, :string
  end
end
