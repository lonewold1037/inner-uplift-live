import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  connect() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
    
    if (!SpeechRecognition) {
      this.buttonTarget.style.display = 'none'
      return
    }

    this.recognition = new SpeechRecognition()
    
    // THE MAGIC SAUCE:
    // true = keep listening even if I pause/breathe (fixes the 20-word limit)
    this.recognition.continuous = true 
    
    // true = show words as I speak them (feels faster)
    this.recognition.interimResults = true 
    
    this.recognition.lang = 'en-US'
    this.isListening = false

    this.recognition.onresult = (event) => {
      // Get the text just from this current speaking session
      const currentTranscript = Array.from(event.results)
        .map(result => result[0].transcript)
        .join('')
      
      // LOGIC UPGRADE: 
      // Instead of replacing the whole value, we append the new speech 
      // to whatever was in the box when we started.
      // This allows you to type a bit, click mic, talk, click stop, type more, click mic...
      const spacing = (this.originalText && this.originalText.length > 0) ? " " : ""
      this.inputTarget.value = this.originalText + spacing + currentTranscript
      
      this.inputTarget.dispatchEvent(new Event('input', { bubbles: true }))
    }

    this.recognition.onend = () => {
      // If the browser stopped it (silence timeout) but we didn't want it to stop,
      // you could technically force a restart here. 
      // But for now, we'll just update the UI so the user knows it stopped.
      this.isListening = false
      this.buttonTarget.classList.remove('text-red-400')
      this.buttonTarget.classList.add('text-white/50')
    }

    this.recognition.onerror = (event) => {
      console.error('Speech recognition error:', event.error)
      this.isListening = false
      this.buttonTarget.classList.remove('text-red-400')
      this.buttonTarget.classList.add('text-white/50')
    }
  }

  toggle() {
    if (this.isListening) {
      this.recognition.stop()
      // UI updates happen in onend()
    } else {
      // SNAPSHOT: Remember what is currently in the box before we start listening
      // This prevents the new speech from overwriting your old notes.
      this.originalText = this.inputTarget.value
      
      this.recognition.start()
      this.isListening = true
      this.buttonTarget.classList.remove('text-white/50')
      this.buttonTarget.classList.add('text-red-400')
    }
  }
}