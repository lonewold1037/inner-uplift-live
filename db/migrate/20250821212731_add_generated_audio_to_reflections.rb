class AddGeneratedAudioToReflections < ActiveRecord::Migration[7.0]
  def change
    add_column :reflections, :generated_audio, :string
  end
end
