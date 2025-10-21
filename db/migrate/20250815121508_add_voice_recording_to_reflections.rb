class AddVoiceRecordingToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :voice_recording, :string
  end
end
