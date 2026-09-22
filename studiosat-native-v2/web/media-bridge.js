/*
 * Studio Sat V2 - ponte mínima de mídia.
 *
 * Responsabilidade única:
 * - usar HLS nativo quando o navegador possui suporte;
 * - usar HLS.js/MSE como compatibilidade quando não possui;
 * - nunca modificar currentTime para "perseguir" a borda ao vivo;
 * - nunca usar AudioContext/Analyser;
 * - nunca permitir playbackRate diferente de 1.0.
 */
(() => {
  let hls = null;

  function audio() {
    const element = document.getElementById("radio-audio");
    if (!element) throw new Error("radio-audio ausente");
    return element;
  }

  function destroyTransport() {
    if (hls) {
      try { hls.destroy(); } catch (_) {}
      hls = null;
    }
  }

  function enforceRate(element) {
    element.defaultPlaybackRate = 1.0;
    if (Math.abs(element.playbackRate - 1.0) > 0.001) {
      element.playbackRate = 1.0;
    }
  }

  async function play(url) {
    const element = audio();

    destroyTransport();
    element.pause();
    element.removeAttribute("src");
    element.load();
    enforceRate(element);

    // Safari/iOS/macOS: HLS nativo.
    if (element.canPlayType("application/vnd.apple.mpegurl")) {
      element.src = url;
      element.load();
      await element.play();
      return true;
    }

    // Chrome/Firefox/Edge: HLS.js somente para transporte HLS -> MSE.
    if (window.Hls && window.Hls.isSupported()) {
      hls = new window.Hls({
        enableWorker: true,
        lowLatencyMode: false,
        maxLiveSyncPlaybackRate: 1.0,
        backBufferLength: 30,
        maxBufferLength: 30,
        maxMaxBufferLength: 60
      });

      await new Promise((resolve, reject) => {
        const onError = (_event, data) => {
          if (!data.fatal) return;
          hls.off(window.Hls.Events.ERROR, onError);
          reject(new Error(`${data.type}/${data.details}`));
        };

        hls.on(window.Hls.Events.ERROR, onError);
        hls.on(window.Hls.Events.MEDIA_ATTACHED, () => hls.loadSource(url));
        hls.on(window.Hls.Events.MANIFEST_PARSED, () => {
          hls.off(window.Hls.Events.ERROR, onError);
          resolve();
        });
        hls.attachMedia(element);
      });

      enforceRate(element);
      await element.play();
      return true;
    }

    throw new Error("Este navegador não oferece HLS nativo nem MSE compatível.");
  }

  function pause() {
    audio().pause();
  }

  function isPlaying() {
    const element = audio();
    return !element.paused && !element.ended;
  }

  function setVolume(value) {
    audio().volume = Math.max(0, Math.min(1, Number(value)));
  }

  // Proteção final: nenhum código, extensão ou callback interno pode deixar
  // a velocidade do elemento audível diferente de 1.0.
  document.addEventListener("DOMContentLoaded", () => {
    const element = audio();
    element.addEventListener("ratechange", () => enforceRate(element));
  });

  window.StudioSatMedia = { play, pause, isPlaying, setVolume };
})();
