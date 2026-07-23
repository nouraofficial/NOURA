// ══════════════════════════════════════════════════════
//  NOURA FOR BUSINESS — SERVICE WORKER
//  Separate from the consumer app's sw.js — own cache name,
//  own app shell, so installing one doesn't affect the other.
// ══════════════════════════════════════════════════════
const CACHE_NAME = 'noura-vendor-shell-v1';
const APP_SHELL = ['vendor.html', 'config.js', 'services.js'];

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

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
