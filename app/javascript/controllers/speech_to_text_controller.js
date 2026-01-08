import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  connect() {
    // Check if browser supports speech recognition
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
    
    if (!SpeechRecognition) {
      this.buttonTarget.style.display = 'none'
      return
    }

    this.recognition = new SpeechRecognition()
    this.recognition.continuous = false
    this.recognition.interimResults = true
    this.recognition.lang = 'en-US'
    this.isListening = false

    this.recognition.onresult = (event) => {
      const transcript = Array.from(event.results)
        .map(result => result[0].transcript)
        .join('')
      
      this.inputTarget.value = transcript
      this.inputTarget.dispatchEvent(new Event('input', { bubbles: true }))
    }

    this.recognition.onend = () => {
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
    } else {
      this.recognition.start()
      this.isListening = true
      this.buttonTarget.classList.remove('text-white/50')
      this.buttonTarget.classList.add('text-red-400')
    }
  }
}