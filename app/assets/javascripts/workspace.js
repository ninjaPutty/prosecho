document.addEventListener('error', (event) => {
  if (event.target instanceof HTMLImageElement && event.target.hasAttribute('data-portrait')) {
    event.target.remove()
  }
}, true)

let progressTimer

function watchRefresh() {
  clearTimeout(progressTimer)
  const progress = document.querySelector('[data-refresh-progress]')
  if (!progress || document.hidden) return

  async function poll() {
    if (!progress.isConnected || document.hidden) return
    try {
      const response = await fetch(progress.dataset.statusUrl, {
        headers: { Accept: 'application/json' }, cache: 'no-store', credentials: 'same-origin'
      })
      if (!response.ok) throw new Error('Progress unavailable')
      const run = await response.json()
      if (!progress.isConnected) return
      if (run.status === 'succeeded' || run.status === 'failed') {
        window.location.reload()
        return
      }
      let message = `Refresh ${run.status}. ${run.page_count} pages saved; ${run.staged_count} records staged.`
      message += ` ${run.duplicate_count || 0} repeated entries merged.`
      if (run.error_code === 'rock_read_failed') {
        message += ` ${run.error_message}`
        if (run.error_details.http_status) message += ` Rock HTTP ${run.error_details.http_status}.`
      } else if (run.error_code === 'rock_not_configured') {
        message += " Waiting for the server's Rock connection configuration. Saved pages are intact."
      }
      if (!run.worker_online) message += ' No directory worker is currently online; saved work will resume when one starts.'
      const state = document.querySelector('[data-refresh-state]')
      if (state && run.status) state.textContent = run.status.charAt(0).toUpperCase() + run.status.slice(1)
      progress.querySelector('[data-refresh-message]').textContent = message
    } catch {
      progress.querySelector('[data-refresh-message]').textContent =
        'Unable to check progress right now. Saved pages are intact; checking again shortly.'
    }
    if (progress.isConnected) progressTimer = setTimeout(poll, 5000)
  }
  progressTimer = setTimeout(poll, 5000)
}

document.addEventListener('turbo:load', watchRefresh)
document.addEventListener('DOMContentLoaded', watchRefresh)
document.addEventListener('visibilitychange', watchRefresh)
document.addEventListener('turbo:before-cache', () => clearTimeout(progressTimer))
