import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  connect() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition

    if (!SpeechRecognition) {
      if (this.hasButtonTarget) this.buttonTarget.style.display = "none"
      return
    }

    // If Turbo reconnects, ensure we don't leave old recognizers alive
    this._teardown()

    this.recognition = new SpeechRecognition()
    this.recognition.continuous = true
    this.recognition.interimResults = true
    this.recognition.lang = "en-US"

    this.isListening = false

    // Buffers
    this.originalText = this.inputTarget.value || ""
    this.confirmedText = ""
    this.lastFinalChunk = ""

    this.recognition.onresult = (event) => {
      let newFinal = ""
      let interim = ""

      for (let i = event.resultIndex; i < event.results.length; i++) {
        const res = event.results[i]
        const transcript = (res[0]?.transcript || "").trim()
        if (!transcript) continue

        if (res.isFinal) {
          // De-dupe repeated final emissions
          if (transcript !== this.lastFinalChunk) {
            newFinal += (newFinal ? " " : "") + transcript
            this.lastFinalChunk = transcript
          }
        } else {
          interim = transcript
        }
      }

      if (newFinal) {
        this.confirmedText = (this.confirmedText ? this.confirmedText + " " : "") + newFinal
      }

      // Always show what we have so far
      const base = [this.originalText.trim(), this.confirmedText.trim()].filter(Boolean).join(" ")
      const display = interim ? [base, interim].filter(Boolean).join(" ") : base

      this.inputTarget.value = display || this.originalText

      // ⚠️ Important: avoid firing extra input events unless you truly need it.
      // If you need it (for a character counter etc), throttle it.
      // this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    this.recognition.onend = () => {
      this.isListening = false
      this._setIdle()
    }

    this.recognition.onerror = (event) => {
      console.error("Speech recognition error:", event.error)
      this.isListening = false
      this._setIdle()
    }

    this._setIdle()
  }

  disconnect() {
    // CRITICAL: prevent zombie recognizers when Turbo swaps DOM
    this._teardown()
  }

  toggle() {
    if (!this.recognition) return

    if (this.isListening) {
      this.recognition.stop()
      return
    }

    // Snapshot what exists before listening starts
    this.originalText = (this.inputTarget.value || "").trim()
    this.confirmedText = ""
    this.lastFinalChunk = ""

    try {
      this.recognition.start()
      this.isListening = true
      this._setListening()
    } catch (e) {
      console.warn("recognition.start() failed (double start?)", e)
    }
  }

  _teardown() {
    if (!this.recognition) return
    try {
      this.recognition.onresult = null
      this.recognition.onend = null
      this.recognition.onerror = null
      this.recognition.stop()
    } catch (_) {
      // ignore
    } finally {
      this.recognition = null
      this.isListening = false
    }
  }

  _setListening() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.classList.remove("text-white/50")
    this.buttonTarget.classList.add("text-red-400")
  }

  _setIdle() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.classList.remove("text-red-400")
    this.buttonTarget.classList.add("text-white/50")
  }
}
