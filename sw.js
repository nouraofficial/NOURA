// ══════════════════════════════════════════════════════
//  NOURA — SERVICE WORKER
//  Required for "Add to Home Screen" install prompts to
//  fire on Chrome/Android. Also caches the app shell so the
//  UI still loads if the network drops mid-session.
// ══════════════════════════════════════════════════════
const CACHE_NAME = 'noura-shell-v1';
const APP_SHELL = ['index.html', 'config.js', 'services.js'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

// Network-first for everything except the cached app shell —
// live data (restaurants, AI, recipes) should never be stale.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
