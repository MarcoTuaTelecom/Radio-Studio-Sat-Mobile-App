const CACHE='studiosat-pwa-v4-reference';
const CORE=[
  '/listen/',
  '/listen/manifest.webmanifest',
  '/listen/icon-192.png',
  '/listen/icon-512.png',
  '/listen/art/hero-studiosat.svg',
  '/listen/art/promo-sunset.svg',
  '/listen/art/station-principal.svg',
  '/listen/art/station-pop.svg',
  '/listen/art/station-rock.svg',
  '/listen/art/station-classicas.svg',
  '/listen/art/station-country.svg'
];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE)));
  self.skipWaiting();
});

self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))));
  self.clients.claim();
});

self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET') return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin || !url.pathname.startsWith('/listen/')) return;

  if(request.mode==='navigate'){
    event.respondWith(
      fetch(request,{cache:'no-store'}).then(response=>{
        if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put('/listen/',copy));}
        return response;
      }).catch(()=>caches.match('/listen/'))
    );
    return;
  }

  const isReferenceAsset=url.pathname.startsWith('/listen/art/');
  if(isReferenceAsset){
    event.respondWith(
      fetch(request,{cache:'no-store'}).then(response=>{
        if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}
        return response;
      }).catch(()=>caches.match(request))
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(cached=>{
      const network=fetch(request).then(response=>{
        if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy));}
        return response;
      }).catch(()=>cached);
      return cached||network;
    })
  );
});