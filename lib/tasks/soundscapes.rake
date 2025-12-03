namespace :soundscapes do
  desc "Upload Zen Meditation soundscapes from Google Drive"
  task upload_zen_batch_1: :environment do
    require 'open-uri'
    
    soundscapes = [
      { 
        file_id: "1owFNquleHL4Bv8BJgJ2nhSxVdRGb8kmb",
        filename: "breath-of-life_5-minutes-320858.mp3",
        name: "Breath of Life",
        category: "Zen Meditation"
      },
      { 
        file_id: "15B7COuVP-Z31cXmCxOYn0dHZ-VUbPHfs",
        filename: "deep-meditation-192828.mp3",
        name: "Deep Meditation",
        category: "Zen Meditation"
      },
      { 
        file_id: "1-tuiybrI9adrWjXWCFz4ElS8cc46ZBLY",
        filename: "path-to-harmony-313385.mp3",
        name: "Path to Harmony",
        category: "Zen Meditation"
      },
      { 
        file_id: "1qy7k4SGAuSWun4Hd9_F56TH_Nxc3Nuax",
        filename: "reflected-light-147979.mp3",
        name: "Reflected Light",
        category: "Zen Meditation"
      }
    ]

    puts "🎵 Starting upload of #{soundscapes.count} Zen Meditation tracks..."

    soundscapes.each do |data|
      if Soundscape.exists?(name: data[:name])
        puts "⏭️  Skipping '#{data[:name]}' - already exists"
        next
      end

      puts "📥 Downloading: #{data[:name]}..."
      
      download_url = "https://drive.google.com/uc?export=download&id=#{data[:file_id]}"
      
      begin
        file = URI.open(download_url)
        
        soundscape = Soundscape.create!(
          name: data[:name],
          category: data[:category]
        )
        
        soundscape.audio_file.attach(
          io: file,
          filename: data[:filename],
          content_type: "audio/mpeg"
        )
        
        puts "✅ Uploaded: #{data[:name]}"
      rescue => e
        puts "❌ Error uploading #{data[:name]}: #{e.message}"
      end
    end

    puts "\n🎉 Upload complete! Total Zen Meditation tracks: #{Soundscape.where(category: 'Zen Meditation').count}"
  end
end