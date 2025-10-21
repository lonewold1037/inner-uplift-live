class RemoveOldAudioColumnsFromReflections < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      remove_column :reflections, :voice_recording, :string if column_exists?(:reflections, :voice_recording)
      remove_column :reflections, :generated_audio, :string if column_exists?(:reflections, :generated_audio)
      remove_column :reflections, :vibe, :string if column_exists?(:reflections, :vibe)
    end
  end
end
