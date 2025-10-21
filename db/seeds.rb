require "open-uri"

puts "🌱 Seeding Soundscapes..."

soundscapes_data = [
  { file: "oceania-waves-ambient-music.mp3",       name: "Oceania Waves",          category: "Oceania" },
  { file: "pixabay-epic-motivational-1.mp3",       name: "Ascension",              category: "Epic Motivational" },
  { file: "meditation-spiritual-music.mp3",        name: "Temple Garden",          category: "Zen Meditation" },
  { file: "lo-fi-ambient-music-with-gentle-rain-sounds.mp3", name: "Midnight Study", category: "Lo-Fi Chill" },
  { file: "cosmic-exploration-soundscape.mp3",     name: "Nebula Drift",           category: "Cosmic Dream" },
  { file: "inspirational-documentary-cinematic-piano.mp3", name: "First Light",     category: "Cinematic Piano" },
  { file: "hip-hop-basketball-hiphop-music.mp3",   name: "Golden Era Groove",      category: "90s Hip-Hop" },
  { file: "romantic-melody-of-the-80s.mp3",        name: "Starlight Serenade",     category: "80s Love Songs" },
  { file: "upbeat-pop-music.mp3",                  name: "Cloud Gazing",           category: "Dream Pop" },
  { file: "voices-of-eternity-church-cathedral-choir.mp3", name: "Hallelujah Chorus", category: "Uplifting Choir" }
]

soundscapes_data.each do |data|
  if Soundscape.exists?(category: data[:category])
    puts "⚪️ Soundscape '#{data[:name]}' already exists, skipping."
    next
  end

  file_path = Rails.root.join("db", "seed_assets", "audio", data[:file])
  unless File.exist?(file_path)
    puts "❌ File missing: #{file_path}, skipping..."
    next
  end

  soundscape = Soundscape.new(
    name: data[:name],
    category: data[:category]
  )

  soundscape.audio_file.attach(
    io: File.open(file_path),
    filename: data[:file],
    content_type: "audio/mpeg"
  )

  if soundscape.save(validate: false)
    puts "✅ Created soundscape: #{data[:name]} (#{data[:category]})"
  else
    puts "❌ Failed to save soundscape #{data[:name]}: #{soundscape.errors.full_messages.join(", ")}"
  end
end

puts "🌲 Seeding complete."
