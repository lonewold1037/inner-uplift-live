# lib/tasks/soundscapes.rake
namespace :soundscapes do
  desc "Batch upload soundscapes from Google Drive with FFmpeg normalization"
  task :batch_upload, [:category] => :environment do |t, args|
    require 'open-uri'
    require 'open3'
    require 'tempfile'
    
    category = args[:category] || 'Epic Motivational'
    
    # Define your soundscapes here with Google Drive file IDs
    soundscapes = {
      'Epic Motivational' => [
        { name: 'Ascension Protocol wo Driving Beat', file_id: '1iDD0M5n4AA4shnyHGEsuN3FwXwMev-7L', filename: 'Ascension_Protocol.mp3' },
        { name: 'Unbreakable', file_id: '1x6VTPPPwIr7vDwPz2Jg552lpildjdABa', filename: 'Unbreakable_epic_mot.mp3' },
        { name: 'The Comeback', file_id: '1Wc8bLkvW9_PvQe3oHSKGdlLfFqcW-4I2', filename: 'The_Comeback.mp3' },
        { name: 'The Gold Medal Favorite', file_id: '1XiCFQE9Vq4SE451Hx5SrnMVHsdgAtG1M', filename: 'The_Gold_Medal.mp3' }
      ],
      'Zen Meditation' => [
        # Your existing zen tracks...
      ]
    }
    
    tracks = soundscapes[category]
    
    unless tracks
      puts "❌ Category '#{category}' not found. Available: #{soundscapes.keys.join(', ')}"
      exit
    end
    
    puts "🎵 Starting upload of #{tracks.count} #{category} tracks..."
    puts "🔧 FFmpeg normalization: loudness -16 LUFS"
    
    tracks.each do |data|
      if Soundscape.exists?(name: data[:name])
        puts "⏭️  Skipping '#{data[:name]}' - already exists"
        next
      end
      
      puts "📥 Downloading: #{data[:name]}..."
      download_url = "https://drive.google.com/uc?export=download&id=#{data[:file_id]}"
      
      begin
        # Download original
        original_file = URI.open(download_url)
        temp_original = Tempfile.new(['original_', '.mp3'], binmode: true)
        temp_original.write(original_file.read)
        temp_original.flush
        
        # Normalize with FFmpeg
        puts "🎛️  Normalizing audio..."
        normalized_file = Tempfile.new(['normalized_', '.mp3'], binmode: true)
        
        normalize_cmd = [
          'ffmpeg', '-y',
          '-i', temp_original.path,
          '-af', 'loudnorm=I=-16:LRA=11:TP=-1.5',
          '-c:a', 'libmp3lame', '-q:a', '2',
          normalized_file.path
        ]
        
        _stdout, stderr, status = Open3.capture3(*normalize_cmd)
        
        unless status.success?
          puts "⚠️  FFmpeg normalization failed: #{stderr}"
          puts "📤 Uploading original file instead..."
          upload_file = temp_original
        else
          puts "✅ Normalization complete"
          upload_file = normalized_file
        end
        
        # Upload to Rails → S3
        soundscape = Soundscape.create!(
          name: data[:name],
          category: category
        )
        
        soundscape.audio_file.attach(
          io: File.open(upload_file.path),
          filename: data[:filename],
          content_type: "audio/mpeg"
        )
        
        puts "✅ Uploaded: #{data[:name]}"
        
      rescue => e
        puts "❌ Error uploading #{data[:name]}: #{e.message}"
      ensure
        temp_original&.close
        temp_original&.unlink
        normalized_file&.close
        normalized_file&.unlink
      end
    end
    
    puts "\n🎉 Upload complete! Total #{category} tracks: #{Soundscape.where(category: category).count}"
  end
  
  desc "List all soundscapes by category"
  task :list => :environment do
    Soundscape.select(:category).distinct.pluck(:category).each do |category|
      count = Soundscape.where(category: category).count
      puts "#{category}: #{count} tracks"
    end
  end
end