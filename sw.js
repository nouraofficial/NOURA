const CACHE = 'noura-campus-v2';
const APP_SHELL = [
  '/',
  '/index.html',
  '/landing.html',
  '/vendor.html',
  '/admin.html',
  '/store.html',
  '/manifest.json',
  '/noura-icon.svg',
  '/mascot-cutout.png'
];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== location.origin) return;
  event.respondWith(caches.match(event.request).then(cached => {
    const network = fetch(event.request).then(res => {
      if (res && res.ok) caches.open(CACHE).then(c => c.put(event.request, res.clone()));
      return res;
    }).catch(() => cached);
    return cached || network;
  }));
});
