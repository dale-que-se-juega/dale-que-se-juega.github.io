const CACHE_NAME = "dale-que-se-juega-v6";
const ARCHIVOS_APP = [
  "./",
  "./index.html",
  "./style.css",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png",
  "./apple-touch-icon.png",
  "./dale-que-se-juega.mp3"
];

self.addEventListener("install", evento => {
  evento.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ARCHIVOS_APP))
  );
  self.skipWaiting();
});

self.addEventListener("activate", evento => {
  evento.waitUntil(
    caches.keys().then(nombres => Promise.all(
      nombres
        .filter(nombre => nombre !== CACHE_NAME)
        .map(nombre => caches.delete(nombre))
    ))
  );
  self.clients.claim();
});

self.addEventListener("fetch", evento => {
  if (evento.request.method !== "GET" || new URL(evento.request.url).origin !== self.location.origin) {
    return;
  }

  evento.respondWith(
    fetch(evento.request)
      .then(respuesta => {
        const copia = respuesta.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(evento.request, copia));
        return respuesta;
      })
      .catch(() => caches.match(evento.request).then(respuesta => respuesta || caches.match("./index.html")))
  );
});
