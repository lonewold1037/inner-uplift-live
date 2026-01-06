# lib/tasks/soundscapes.rake
namespace :soundscapes do
  desc "Batch upload soundscapes from Google Drive with FFmpeg normalization"
  task :batch_upload, [:category] => :environment do |t, args|
    require 'open-uri'
    require 'open3'
    require 'tempfile'
    
    category = args[:category] || 'Oceania'
    
    # Define your soundscapes here with Google Drive file IDs
    soundscapes = {
      'Epic Motivational' => [
        { name: 'Ascension Protocol wo Driving Beat', file_id: '1iDD0M5n4AA4shnyHGEsuN3FwXwMev-7L', filename: 'Ascension_Protocol.mp3' },
        { name: 'Unbreakable', file_id: '1x6VTPPPwIr7vDwPz2Jg552lpildjdABa', filename: 'Unbreakable_epic_mot.mp3' },
        { name: 'The Comeback', file_id: '1Wc8bLkvW9_PvQe3oHSKGdlLfFqcW-4I2', filename: 'The_Comeback.mp3' },
        { name: 'The Gold Medal Favorite', file_id: '1XiCFQE9Vq4SE451Hx5SrnMVHsdgAtG1M', filename: 'The_Gold_Medal.mp3' }
      ],
      'Oceania' => [
        { name: 'Oceania Favorite', file_id: '1TMb777D3i_0Dx_RYnWNpqR-nwsXwVsHC', filename: 'oceania_1.mp3' },
        { name: 'Oceanic Choir Meditation', file_id: '1Uq5axpIXMLEomCRqqretY_2QhQ8Aho8O', filename: 'oceania_2.mp3' },
        { name: 'Timeless Expanse', file_id: '1Be3bd3FVmab8tdmwM1-FWTMiIxwL3tVl', filename: 'oceania_3.mp3' }
      ],
      'Lo-Fi Chill' => [
        { name: 'Soft Confidence', file_id: '1ZWZTAitvv9ysHoDSYRz0E6pNUP8JDBlv', filename: 'lofi_1.mp3' },
        { name: 'Gentle Rise', file_id: '1HfHDYydY2gFHDBEY7SXEIeRaqxKYnJ7L', filename: 'lofi_2.mp3' },
        { name: 'Golden Blick Groove', file_id: '14Id_Q44bnyjA4h-SBTT6tMi035_f8CTc', filename: 'lofi_3.mp3' }
      ],
      'Cinematic Piano' => [
        { name: 'A Door Opens Inside You', file_id: '1WaTI7ofNKD7Joy0fXWjQG0vCssP8R92g', filename: 'piano_1.mp3' },
        { name: 'The Quiet Hero', file_id: '1THsr_hjo-yy9F_wXdxbCsWtEDodKbFOy', filename: 'piano_2.mp3' },
        { name: 'Echoes of Resolve', file_id: '1FUUefL9-ZsOkG0kbZTR_14X8F5sOI2Q4', filename: 'piano_3.mp3' }
      ],
      'Inspiring Synth' => [
        { name: 'Inspiring Synth 1', file_id: '1YHxEvfaRaK1VvDufke4xaFpx3TbHhbLi', filename: 'inspiring_synth_1.mp3' },
        { name: 'Inspiring Synth 2', file_id: '14EXG_la0qI09tzms9MGUav7CjQHvEYpg', filename: 'inspiring_synth_2.mp3' },
        { name: 'Inspiring Synth 3', file_id: '15Stq_ql7PVfOQIu7CBBjJy_0uMleTl7X', filename: 'inspiring_synth_3.mp3' }
      ],
      '80s Love Songs' => [
        { name: '80s Love Songs 1', file_id: '1hhYmQmlRgLB5YNDFeQR8xvVqc8RB9txZ', filename: '80s_love_songs_1.mp3' },
        { name: '80s Love Songs 2', file_id: '1-XPgjl6uM3Q0CBRvcNWGVaPuL5_EnriZ', filename: '80s_love_songs_2.mp3' }
      ],
      '90s Hip-Hop' => [
        { name: '90s Hip-Hop 1', file_id: '141ok2ph5rr-h8vPOupOrOO5feSPO0abL', filename: '90s_hip_hop_1.mp3' },
        { name: '90s Hip-Hop 2', file_id: '1bGs1oMlejEHw1DAYLGQNltEDvvPgkgwR', filename: '90s_hip_hop_2.mp3' }
      ],
      'Cosmic Dream' => [
        { name: 'Nebula Heartbeat', file_id: '1pt8hjT2abB91VaFI0jIiqBDJ9EayL4Fg', filename: 'cosmic_1.mp3' },
        { name: 'Starborne Drift', file_id: '1foE13OuBUesccp-kM91zA1edjUuaFGU6', filename: 'cosmic_2.mp3' }
      ],
      'Uplifting Choir' => [
        { name: 'Choir On The Fly', file_id: '1YKTLM3l5-P4l4wHIFg-Br5r5JdEaoNKW', filename: 'choir_1.mp3' },
        { name: 'Choir Deep Ascension Boring', file_id: '1CT41RGzt1HZAz0U3ji0wNfkPRABFyhNa', filename: 'choir_2.mp3' },
        { name: 'Celesial Uprising', file_id: '1WXhEXWsr7iHRwnLzThz_aeLywC06G3Ix', filename: 'choir_3.mp3' }
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