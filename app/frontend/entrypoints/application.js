// Import CSS
import './application.css'

// Import and start Turbo
import { Turbo } from '@hotwired/turbo-rails'
document.addEventListener('turbo:before-cache', () => {
  document.documentElement.setAttribute('data-turbo-cache', 'false')
})

// Import Action Cable
import * as ActionCable from '@rails/actioncable'

// Import Stimulus
import { Application } from '@hotwired/stimulus'
import { registerControllers } from 'stimulus-vite-helpers'

// Start Stimulus
const application = Application.start()
window.Stimulus = application

// Register controllers
registerControllers(application, import.meta.glob('../controllers/**/*_controller.js', { eager: true }))

// Expose ActionCable
window.cable = ActionCable.createConsumer()